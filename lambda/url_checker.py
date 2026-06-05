import json
import boto3
import urllib.request
import urllib.error
import time
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

CHECKS_TABLE = os.environ.get('CHECKS_TABLE_NAME', 'uptime-checks')
URLS_TABLE = os.environ.get('URLS_TABLE_NAME', 'monitored-urls')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', 'arn:aws:sns:us-east-1:196750375574:cloudops-uptime-alerts')

checks_table = dynamodb.Table(CHECKS_TABLE)
urls_table = dynamodb.Table(URLS_TABLE)
sns = boto3.client('sns', region_name='us-east-1')

def lambda_handler(event, context):
    urls = get_monitored_urls()

    if not urls:
        print("No URLs in monitored-urls table. Using fallback defaults.")
        urls = ["https://google.com", "https://github.com", "https://amazon.com"]

    results = []
    for url in urls:
        result = check_url(url)
        save_to_dynamodb(result)
        if not result['is_up']:
            send_alert(result)
        results.append(result)
        print(f"Checked {url}: up={result['is_up']} status={result['status_code']} latency={result['latency_ms']}ms")

    return {
        'statusCode': 200,
        'body': json.dumps(results)
    }

def get_monitored_urls():
    try:
        response = urls_table.scan()
        urls = [item['url'] for item in response.get('Items', [])]
        print(f"Found {len(urls)} URLs in monitored-urls table: {urls}")
        return urls
    except Exception as e:
        print(f"Error reading monitored-urls table: {str(e)}")
        return []

def check_url(url):
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    start_time = time.time()

    try:
        req = urllib.request.Request(
            url,
            headers={'User-Agent': 'CloudOps-Uptime-Monitor/1.0'}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            status_code = response.getcode()
            latency_ms = round((time.time() - start_time) * 1000)
            is_up = status_code < 400

    except urllib.error.HTTPError as e:
        status_code = e.code
        latency_ms = round((time.time() - start_time) * 1000)
        is_up = False

    except Exception as e:
        status_code = 0
        latency_ms = round((time.time() - start_time) * 1000)
        is_up = False
        print(f"Error checking {url}: {str(e)}")

    return {
        'url': url,
        'timestamp': timestamp,
        'status_code': status_code,
        'latency_ms': latency_ms,
        'is_up': is_up
    }

def save_to_dynamodb(result):
    checks_table.put_item(Item={
        'url': result['url'],
        'timestamp': result['timestamp'],
        'status_code': result['status_code'],
        'latency_ms': result['latency_ms'],
        'is_up': result['is_up']
    })

def send_alert(result):
    message = f"""
CloudOps Uptime Monitor — ALERT

URL is DOWN: {result['url']}
Timestamp: {result['timestamp']}
Status Code: {result['status_code']}
Latency: {result['latency_ms']}ms

Immediate action may be required.
— CloudOps Uptime Monitor
"""
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[DOWN] {result['url']}",
        Message=message
    )
    print(f"Alert sent for {result['url']}")