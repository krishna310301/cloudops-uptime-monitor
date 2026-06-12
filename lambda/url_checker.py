import json
import boto3
import urllib.request
import urllib.error
import time
import os
from datetime import datetime, timezone, timedelta

try:
    from .url_validation import validate_monitor_url
except ImportError:
    from url_validation import validate_monitor_url

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
        previous_status = get_previous_status(url)
        result = check_url(url)
        save_to_dynamodb(result)
        alert_type = classify_status_change(previous_status, result['is_up'])
        if alert_type:
            send_alert(result, alert_type)
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

    is_valid, reason = validate_monitor_url(url, resolve_host=True)
    if not is_valid:
        print(f"Blocked unsafe URL {url}: {reason}")
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
        opener = urllib.request.build_opener(SafeRedirectHandler)
        with opener.open(req, timeout=10) as response:  # nosec B310
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

class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        is_valid, reason = validate_monitor_url(newurl, resolve_host=True)
        if not is_valid:
            raise urllib.error.HTTPError(
                req.full_url,
                403,
                f"Blocked unsafe redirect: {reason}",
                headers,
                fp
            )

        return super().redirect_request(req, fp, code, msg, headers, newurl)

def get_previous_status(url):
    try:
        response = latest_status_table.get_item(Key={'url': url})
        item = response.get('Item')
        if item is None:
            return None

        return bool(item.get('is_up'))
    except Exception as e:
        print(f"Could not read previous status for {url}: {str(e)}")
        return None

def classify_status_change(previous_is_up, current_is_up):
    if previous_is_up is None:
        return 'down' if not current_is_up else None

    if previous_is_up and not current_is_up:
        return 'down'

    if not previous_is_up and current_is_up:
        return 'recovery'

    return None

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

def send_alert(result, alert_type='down'):
    if alert_type == 'recovery':
        subject_prefix = 'RECOVERY'
        headline = 'URL has RECOVERED'
        action = 'No immediate action required. Continue watching recent checks.'
    else:
        subject_prefix = 'DOWN'
        headline = 'URL is DOWN'
        action = 'Immediate action may be required.'

    message = f"""
CloudOps Uptime Monitor — {subject_prefix}

{headline}: {result['url']}
Timestamp: {result['timestamp']}
Status Code: {result['status_code']}
Latency: {result['latency_ms']}ms

{action}
— CloudOps Uptime Monitor
"""
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[{subject_prefix}] {result['url']}",
        Message=message
    )
    print(f"{subject_prefix} alert sent for {result['url']}")

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
