import json
import os
import boto3
from decimal import Decimal
from json import JSONDecodeError
from urllib.parse import unquote

try:
    from .url_validation import normalize_url, validate_monitor_url
except ImportError:
    from url_validation import normalize_url, validate_monitor_url

class InvalidJsonBody(Exception):
    pass

AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
CHECKS_TABLE = os.environ.get('CHECKS_TABLE_NAME', 'uptime-checks')
URLS_TABLE = os.environ.get('URLS_TABLE_NAME', 'monitored-urls')
LATEST_STATUS_TABLE = os.environ.get('LATEST_STATUS_TABLE_NAME', 'latest-url-status')
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get('ALLOWED_ORIGINS', '').split(',')
    if origin.strip()
]
METRIC_NAMESPACE = os.environ.get('METRIC_NAMESPACE', 'CloudOps/UptimeMonitor')

dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
checks_table = dynamodb.Table(CHECKS_TABLE)
urls_table = dynamodb.Table(URLS_TABLE)
latest_status_table = dynamodb.Table(LATEST_STATUS_TABLE)
cloudwatch = boto3.client('cloudwatch', region_name=AWS_REGION)

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj)
        return super().default(obj)

def lambda_handler(event, context):
    method = event.get('httpMethod')
    path = event.get('path', '')
    headers = response_headers(event)
    
    if method == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}
    
    try:
        if method == 'GET' and path == '/urls':
            return get_urls(headers)
        
        elif method == 'POST' and path == '/urls':
            body = parse_json_body(event)
            return add_url(body.get('url'), headers)
        
        elif method == 'DELETE' and path == '/urls':
            body = parse_json_body(event)
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
    
    except InvalidJsonBody:
        return error_response(400, 'Request body must be valid JSON', headers)

    except Exception as e:
        print(f"Error: {str(e)}")
        return error_response(500, 'Internal server error', headers)

def response_headers(event):
    headers = event.get('headers') or {}
    request_origin = headers.get('origin') or headers.get('Origin')
    allow_origin = ALLOWED_ORIGINS[0] if ALLOWED_ORIGINS else ''

    if request_origin and request_origin in ALLOWED_ORIGINS:
        allow_origin = request_origin

    response = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Headers': 'Content-Type,X-Api-Key',
        'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
    }

    if allow_origin:
        response['Access-Control-Allow-Origin'] = allow_origin
        response['Vary'] = 'Origin'

    return response

def parse_json_body(event):
    body = event.get('body') or '{}'
    try:
        parsed = json.loads(body)
    except (JSONDecodeError, ValueError, SystemError) as exc:
        raise InvalidJsonBody() from exc

    if not isinstance(parsed, dict):
        raise InvalidJsonBody()

    return parsed

def error_response(status_code, message, headers):
    return {
        'statusCode': status_code,
        'headers': headers,
        'body': json.dumps({'error': message})
    }

def scan_all(table):
    items = []
    scan_kwargs = {}

    while True:
        response = table.scan(**scan_kwargs)
        items.extend(response.get('Items', []))

        if 'LastEvaluatedKey' not in response:
            return items

        scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']

def get_urls(headers):
    urls = [item['url'] for item in scan_all(urls_table)]

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
            'body': json.dumps({'error': 'Valid public http or https URL is required'})
        }

    urls_table.put_item(Item={'url': normalized_url})
    put_metric('URLAdded', 1, 'Count')
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
            'body': json.dumps({'error': 'Valid public http or https URL is required'})
        }

    urls_table.delete_item(Key={'url': normalized_url})
    latest_status_table.delete_item(Key={'url': normalized_url})
    put_metric('URLDeleted', 1, 'Count')
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'message': f'Deleted {normalized_url}'})
    }

def get_status(headers):
    results = scan_all(latest_status_table)
    results.sort(key=lambda x: x['url'])
    put_metric('StatusLookupRecordsRead', len(results), 'Count')

    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({'results': results}, cls=DecimalEncoder)
    }

def is_valid_url(value):
    is_valid, _reason = validate_monitor_url(value, resolve_host=False)
    return is_valid

def put_metric(metric_name, value, unit):
    try:
        cloudwatch.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=[{
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit
            }]
        )
    except Exception as e:
        print(f"Failed to publish metric {metric_name}: {str(e)}")
