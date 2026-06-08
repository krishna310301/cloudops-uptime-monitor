import json
import os
import boto3
from decimal import Decimal
from urllib.parse import unquote
from urllib.parse import urlparse

AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
CHECKS_TABLE = os.environ.get('CHECKS_TABLE_NAME', 'uptime-checks')
URLS_TABLE = os.environ.get('URLS_TABLE_NAME', 'monitored-urls')

dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
checks_table = dynamodb.Table(CHECKS_TABLE)
urls_table = dynamodb.Table(URLS_TABLE)

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj)
        return super().default(obj)

def lambda_handler(event, context):
    method = event.get('httpMethod')
    path = event.get('path', '')
    
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
    }
    
    if method == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}
    
    try:
        if method == 'GET' and path == '/urls':
            return get_urls(headers)
        
        elif method == 'POST' and path == '/urls':
            body = json.loads(event.get('body', '{}'))
            return add_url(body.get('url'), headers)
        
        elif method == 'DELETE' and path == '/urls':
            body = json.loads(event.get('body', '{}'))
            return delete_url(body.get('url'), headers)

        elif method == 'DELETE' and path.startswith('/urls/'):
            encoded_url = path.removeprefix('/urls/')
            return delete_url(unquote(encoded_url), headers)
        
        elif method == 'GET' and path == '/status':
            return get_status(headers)
        
        else:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({'error': 'Route not found'})
            }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': str(e)})
        }

def get_urls(headers):
    urls = []
    scan_kwargs = {}

    while True:
        response = urls_table.scan(**scan_kwargs)
        urls.extend(item['url'] for item in response.get('Items', []))

        if 'LastEvaluatedKey' not in response:
            break

        scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']

    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'urls': sorted(urls)})
    }

def add_url(url, headers):
    if not url:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'URL is required'})
        }
    normalized_url = normalize_url(url)

    if not is_valid_url(normalized_url):
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'Valid http or https URL is required'})
        }

    urls_table.put_item(Item={'url': normalized_url})
    return {
        'statusCode': 201,
        'headers': headers,
        'body': json.dumps({'message': f'Added {normalized_url}'})
    }

def delete_url(url, headers):
    if not url:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'URL is required'})
        }
    normalized_url = normalize_url(url)

    if not is_valid_url(normalized_url):
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'Valid http or https URL is required'})
        }

    urls_table.delete_item(Key={'url': normalized_url})
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'message': f'Deleted {normalized_url}'})
    }

def get_status(headers):
    # Only show results for currently monitored URLs
    monitored_urls = set()
    url_scan_kwargs = {}

    while True:
        monitored = urls_table.scan(**url_scan_kwargs)
        monitored_urls.update(item['url'] for item in monitored.get('Items', []))

        if 'LastEvaluatedKey' not in monitored:
            break

        url_scan_kwargs['ExclusiveStartKey'] = monitored['LastEvaluatedKey']

    items = []
    checks_scan_kwargs = {}

    while True:
        response = checks_table.scan(**checks_scan_kwargs)
        items.extend(response.get('Items', []))

        if 'LastEvaluatedKey' not in response:
            break

        checks_scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']

    latest = {}
    for item in items:
        url = item['url']
        if url not in monitored_urls:
            continue
        if url not in latest or item['timestamp'] > latest[url]['timestamp']:
            latest[url] = item

    results = list(latest.values())
    results.sort(key=lambda x: x['url'])

    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'results': results}, cls=DecimalEncoder)
    }

def normalize_url(value):
    url = (value or '').strip()
    if not url:
        return ''

    if not url.startswith(('http://', 'https://')):
        url = f'https://{url}'

    return url

def is_valid_url(value):
    try:
        parsed = urlparse(value)
        return parsed.scheme in ('http', 'https') and bool(parsed.netloc)
    except Exception:
        return False
