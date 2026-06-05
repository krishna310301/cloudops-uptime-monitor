import json
import os
import boto3
from boto3.dynamodb.conditions import Key
from decimal import Decimal

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
        
        elif method == 'DELETE' and '/urls/' in path:
            url = None
            if event.get('pathParameters'):
                url = event['pathParameters'].get('url')
            if not url:
                url = path.split('/urls/')[-1]
            if url:
                from urllib.parse import unquote
                url = unquote(url)
            return delete_url(url, headers)
        
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
    response = urls_table.scan()
    urls = [item['url'] for item in response.get('Items', [])]
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'urls': urls})
    }

def add_url(url, headers):
    if not url:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'URL is required'})
        }
    
    urls_table.put_item(Item={'url': url})
    return {
        'statusCode': 201,
        'headers': headers,
        'body': json.dumps({'message': f'Added {url}'})
    }

def delete_url(url, headers):
    if not url:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'URL is required'})
        }
    
    urls_table.delete_item(Key={'url': url})
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'message': f'Deleted {url}'})
    }

def get_status(headers):
    # Only show results for currently monitored URLs
    monitored = urls_table.scan()
    monitored_urls = {item['url'] for item in monitored.get('Items', [])}

    response = checks_table.scan()
    items = response.get('Items', [])

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