import json
import boto3
import urllib.request
import urllib.error
import time
import os
from datetime import datetime, timezone, timedelta

AWS_REGION = os.environ.get('AWS_REGION', os.environ.get('AWS_DEFAULT_REGION', 'us-east-1'))
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)

CHECKS_TABLE = os.environ.get('CHECKS_TABLE_NAME', 'uptime-checks')
URLS_TABLE = os.environ.get('URLS_TABLE_NAME', 'monitored-urls')
LATEST_STATUS_TABLE = os.environ.get('LATEST_STATUS_TABLE_NAME', 'latest-url-status')
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
RESULT_TTL_DAYS = int(os.environ.get('RESULT_TTL_DAYS', '30'))
METRIC_NAMESPACE = os.environ.get('METRIC_NAMESPACE', 'CloudOps/UptimeMonitor')

checks_table = dynamodb.Table(CHECKS_TABLE)
urls_table = dynamodb.Table(URLS_TABLE)
latest_status_table = dynamodb.Table(LATEST_STATUS_TABLE)
sns = boto3.client('sns', region_name=AWS_REGION)
cloudwatch = boto3.client('cloudwatch', region_name=AWS_REGION)

def lambda_handler(event, context):
    run_start = time.time()
    urls = get_monitored_urls()

    if not urls:
        print("No URLs in monitored-urls table. Using fallback defaults.")
        urls = ["https://google.com", "https://github.com", "https://amazon.com"]

    results = []
    alerts_sent = 0
    for url in urls:
        result = check_url(url)
        save_to_dynamodb(result)
        if not result['is_up']:
            send_alert(result)
            alerts_sent += 1
        results.append(result)
        print(f"Checked {url}: up={result['is_up']} status={result['status_code']} latency={result['latency_ms']}ms")

    publish_check_metrics(results, alerts_sent, run_start)

    return {
        'statusCode': 200,
        'body': json.dumps(results)
    }

def get_monitored_urls():
    try:
        urls = []
        scan_kwargs = {}

        while True:
            response = urls_table.scan(**scan_kwargs)
            urls.extend(item['url'] for item in response.get('Items', []))

            if 'LastEvaluatedKey' not in response:
                break

            scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']

        print(f"Found {len(urls)} URLs in monitored-urls table: {urls}")
        return urls
    except Exception as e:
        print(f"Error reading monitored-urls table: {str(e)}")
        return []

def check_url(url):
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    start_time = time.time()

    if not is_supported_url(url):
        return {
            'url': url,
            'timestamp': timestamp,
            'status_code': 0,
            'latency_ms': 0,
            'is_up': False
        }

    try:
        req = urllib.request.Request(
            url,
            headers={'User-Agent': 'CloudOps-Uptime-Monitor/1.0'}
        )
        # is_supported_url restricts checks to http/https before urlopen.
        with urllib.request.urlopen(req, timeout=10) as response:  # nosec B310
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

def is_supported_url(url):
    return url.startswith(('http://', 'https://'))

def save_to_dynamodb(result):
    ttl = int((datetime.now(timezone.utc) + timedelta(days=RESULT_TTL_DAYS)).timestamp())

    item = {
        'url': result['url'],
        'timestamp': result['timestamp'],
        'status_code': result['status_code'],
        'latency_ms': result['latency_ms'],
        'is_up': result['is_up'],
        'ttl': ttl
    }

    checks_table.put_item(Item=item)
    latest_status_table.put_item(Item=item)

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

def publish_check_metrics(results, alerts_sent, run_start):
    urls_checked = len(results)
    urls_down = sum(1 for result in results if not result['is_up'])
    run_duration_ms = round((time.time() - run_start) * 1000)
    monitored_url_count = urls_checked
    metric_data = [
        {'MetricName': 'URLsChecked', 'Value': urls_checked, 'Unit': 'Count'},
        {'MetricName': 'URLsDown', 'Value': urls_down, 'Unit': 'Count'},
        {'MetricName': 'AlertsSent', 'Value': alerts_sent, 'Unit': 'Count'},
        {'MetricName': 'MonitoredURLCount', 'Value': monitored_url_count, 'Unit': 'Count'},
        {'MetricName': 'CheckRunDurationMs', 'Value': run_duration_ms, 'Unit': 'Milliseconds'},
    ]

    for result in results:
        metric_data.append({
            'MetricName': 'URLCheckLatencyMs',
            'Value': result['latency_ms'],
            'Unit': 'Milliseconds',
            'Dimensions': [{'Name': 'URL', 'Value': result['url']}]
        })

    try:
        for index in range(0, len(metric_data), 20):
            cloudwatch.put_metric_data(
                Namespace=METRIC_NAMESPACE,
                MetricData=metric_data[index:index + 20]
            )
    except Exception as e:
        print(f"Failed to publish check metrics: {str(e)}")
