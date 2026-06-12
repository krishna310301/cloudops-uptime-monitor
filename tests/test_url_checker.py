import importlib
import os
import sys
import time
import types
import unittest
from unittest.mock import patch


class FakeDynamoResource:
    def Table(self, _name):
        return FakeTable()


class FakeTable:
    def __init__(self, pages=None):
        self.items = []
        self.pages = pages
        self.scan_calls = 0

    def put_item(self, Item):
        self.items.append(Item)

    def get_item(self, Key):
        for item in reversed(self.items):
            if item.get("url") == Key["url"]:
                return {"Item": item}

        return {}

    def scan(self, **_kwargs):
        if self.pages is not None:
            page = self.pages[self.scan_calls]
            self.scan_calls += 1
            return page

        return {"Items": self.items}


class FakeSnsClient:
    def __init__(self):
        self.published = []

    def publish(self, **_kwargs):
        self.published.append(_kwargs)
        return {"MessageId": "test-message-id"}


class FakeCloudWatchClient:
    def __init__(self):
        self.metric_calls = []

    def put_metric_data(self, **kwargs):
        self.metric_calls.append(kwargs)
        return {}


def load_url_checker():
    fake_sns = FakeSnsClient()
    fake_cloudwatch = FakeCloudWatchClient()

    def fake_client(service_name, *_args, **_kwargs):
        if service_name == "sns":
            return fake_sns
        if service_name == "cloudwatch":
            return fake_cloudwatch
        raise AssertionError(f"Unexpected client: {service_name}")

    fake_boto3 = types.SimpleNamespace(
        resource=lambda *_args, **_kwargs: FakeDynamoResource(),
        client=fake_client,
    )

    with patch.dict(sys.modules, {"boto3": fake_boto3}), patch.dict(
        os.environ,
        {"SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test"},
    ):
        return importlib.reload(importlib.import_module("lambda.url_checker"))


class UrlCheckerTests(unittest.TestCase):
    def test_save_to_dynamodb_writes_ttl_and_latest_status(self):
        url_checker = load_url_checker()
        checks_table = FakeTable()
        latest_table = FakeTable()
        url_checker.checks_table = checks_table
        url_checker.latest_status_table = latest_table
        url_checker.RESULT_TTL_DAYS = 30

        now = int(time.time())
        url_checker.save_to_dynamodb({
            "url": "https://example.com",
            "timestamp": "2026-06-07T00:00:00Z",
            "status_code": 200,
            "latency_ms": 123,
            "is_up": True,
        })

        self.assertEqual(len(checks_table.items), 1)
        self.assertEqual(latest_table.items, checks_table.items)
        self.assertGreaterEqual(checks_table.items[0]["ttl"], now + (29 * 24 * 60 * 60))
        self.assertLessEqual(checks_table.items[0]["ttl"], now + (31 * 24 * 60 * 60))

    def test_get_monitored_urls_paginates_results(self):
        url_checker = load_url_checker()
        url_checker.urls_table = FakeTable(pages=[
            {
                "Items": [{"url": "https://a.example.com"}],
                "LastEvaluatedKey": {"url": "https://a.example.com"},
            },
            {"Items": [{"url": "https://b.example.com"}]},
        ])

        urls = url_checker.get_monitored_urls()

        self.assertEqual(urls, ["https://a.example.com", "https://b.example.com"])

    def test_publish_check_metrics_emits_operational_metrics(self):
        url_checker = load_url_checker()
        cloudwatch = FakeCloudWatchClient()
        url_checker.cloudwatch = cloudwatch

        url_checker.publish_check_metrics([
            {
                "url": "https://up.example.com",
                "latency_ms": 120,
                "is_up": True,
            },
            {
                "url": "https://down.example.com",
                "latency_ms": 900,
                "is_up": False,
            },
        ], alerts_sent=1, run_start=time.time())

        metric_names = {
            metric["MetricName"]
            for call in cloudwatch.metric_calls
            for metric in call["MetricData"]
        }

        self.assertIn("URLsChecked", metric_names)
        self.assertIn("URLsDown", metric_names)
        self.assertIn("AlertsSent", metric_names)
        self.assertIn("MonitoredURLCount", metric_names)
        self.assertIn("CheckRunDurationMs", metric_names)
        self.assertIn("URLCheckLatencyMs", metric_names)

    def test_classify_status_change_deduplicates_persistent_down_state(self):
        url_checker = load_url_checker()

        self.assertEqual(url_checker.classify_status_change(True, False), "down")
        self.assertIsNone(url_checker.classify_status_change(False, False))
        self.assertEqual(url_checker.classify_status_change(False, True), "recovery")
        self.assertIsNone(url_checker.classify_status_change(True, True))
        self.assertEqual(url_checker.classify_status_change(None, False), "down")
        self.assertIsNone(url_checker.classify_status_change(None, True))

    def test_send_alert_uses_recovery_subject(self):
        url_checker = load_url_checker()
        sns = FakeSnsClient()
        url_checker.sns = sns

        url_checker.send_alert({
            "url": "https://example.com",
            "timestamp": "2026-06-12T00:00:00Z",
            "status_code": 200,
            "latency_ms": 50,
        }, "recovery")

        self.assertEqual(sns.published[0]["Subject"], "[RECOVERY] https://example.com")
        self.assertIn("RECOVERED", sns.published[0]["Message"])

    def test_check_url_blocks_unsafe_metadata_target(self):
        url_checker = load_url_checker()

        result = url_checker.check_url("http://169.254.169.254/latest/meta-data")

        self.assertFalse(result["is_up"])
        self.assertEqual(result["status_code"], 0)
        self.assertEqual(result["latency_ms"], 0)

    def test_checker_sends_only_state_change_alerts(self):
        url_checker = load_url_checker()
        sns = FakeSnsClient()
        url_checker.sns = sns
        url_checker.urls_table = FakeTable()
        url_checker.urls_table.items = [{"url": "https://example.com"}]
        url_checker.checks_table = FakeTable()
        url_checker.latest_status_table = FakeTable()

        with patch.object(url_checker, "check_url", return_value={
            "url": "https://example.com",
            "timestamp": "2026-06-12T00:00:00Z",
            "status_code": 500,
            "latency_ms": 100,
            "is_up": False,
        }):
            first_response = url_checker.lambda_handler({}, None)
            second_response = url_checker.lambda_handler({}, None)

        self.assertEqual(first_response["statusCode"], 200)
        self.assertEqual(second_response["statusCode"], 200)
        self.assertEqual(len(sns.published), 1)
        self.assertEqual(sns.published[0]["Subject"], "[DOWN] https://example.com")

    def test_checker_sends_recovery_after_down_state(self):
        url_checker = load_url_checker()
        sns = FakeSnsClient()
        url_checker.sns = sns
        url_checker.urls_table = FakeTable()
        url_checker.urls_table.items = [{"url": "https://example.com"}]
        url_checker.checks_table = FakeTable()
        url_checker.latest_status_table = FakeTable()
        url_checker.latest_status_table.items = [{
            "url": "https://example.com",
            "timestamp": "2026-06-12T00:00:00Z",
            "status_code": 500,
            "latency_ms": 100,
            "is_up": False,
        }]

        with patch.object(url_checker, "check_url", return_value={
            "url": "https://example.com",
            "timestamp": "2026-06-12T00:05:00Z",
            "status_code": 200,
            "latency_ms": 75,
            "is_up": True,
        }):
            response = url_checker.lambda_handler({}, None)

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(sns.published), 1)
        self.assertEqual(sns.published[0]["Subject"], "[RECOVERY] https://example.com")


if __name__ == "__main__":
    unittest.main()
