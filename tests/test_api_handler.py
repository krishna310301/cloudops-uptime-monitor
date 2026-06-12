import importlib
import os
import sys
import types
import unittest
from unittest.mock import patch


class FakeDynamoResource:
    def Table(self, _name):
        return FakeTable()


class FakeCloudWatchClient:
    def __init__(self):
        self.metric_calls = []

    def put_metric_data(self, **kwargs):
        self.metric_calls.append(kwargs)
        return {}


class FakeTable:
    def __init__(self, pages=None):
        self.items = []
        self.pages = pages
        self.scan_calls = 0

    def put_item(self, Item):
        self.items.append(Item)

    def delete_item(self, Key):
        self.deleted_key = Key

    def scan(self, **_kwargs):
        if self.pages is not None:
            page = self.pages[self.scan_calls]
            self.scan_calls += 1
            return page

        return {"Items": self.items}


def load_api_handler():
    fake_cloudwatch = FakeCloudWatchClient()
    fake_boto3 = types.SimpleNamespace(
        resource=lambda *_args, **_kwargs: FakeDynamoResource(),
        client=lambda *_args, **_kwargs: fake_cloudwatch,
    )
    with patch.dict(sys.modules, {"boto3": fake_boto3}), patch.dict(
        os.environ,
        {
            "ALLOWED_ORIGINS": "https://dashboard.example.com",
            "LATEST_STATUS_TABLE_NAME": "latest-url-status",
        },
    ):
        return importlib.reload(importlib.import_module("lambda.api_handler"))


class ApiHandlerTests(unittest.TestCase):
    def test_normalize_url_adds_https(self):
        api_handler = load_api_handler()

        self.assertEqual(api_handler.normalize_url("example.com"), "https://example.com")

    def test_is_valid_url_rejects_non_http(self):
        api_handler = load_api_handler()

        self.assertFalse(api_handler.is_valid_url("ftp://example.com"))
        self.assertTrue(api_handler.is_valid_url("https://example.com"))

    def test_is_valid_url_rejects_unsafe_targets(self):
        api_handler = load_api_handler()

        unsafe_urls = [
            "http://localhost:8080",
            "http://service.localhost",
            "http://127.0.0.1",
            "http://10.0.0.10",
            "http://172.16.0.10",
            "http://192.168.1.10",
            "http://169.254.169.254/latest/meta-data",
            "http://[::1]",
        ]

        for url in unsafe_urls:
            with self.subTest(url=url):
                self.assertFalse(api_handler.is_valid_url(url))

    def test_add_url_stores_normalized_url(self):
        api_handler = load_api_handler()
        table = FakeTable()
        api_handler.urls_table = table

        response = api_handler.add_url("example.com", {})

        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(table.items, [{"url": "https://example.com"}])

    def test_add_url_rejects_unsafe_target(self):
        api_handler = load_api_handler()
        table = FakeTable()
        api_handler.urls_table = table

        response = api_handler.add_url("http://169.254.169.254/latest/meta-data", {})

        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(table.items, [])
        self.assertIn("public http or https", response["body"])

    def test_response_headers_use_allowed_origin_not_wildcard(self):
        api_handler = load_api_handler()

        headers = api_handler.response_headers({
            "headers": {"Origin": "https://dashboard.example.com"}
        })

        self.assertEqual(headers["Access-Control-Allow-Origin"], "https://dashboard.example.com")
        self.assertNotEqual(headers["Access-Control-Allow-Origin"], "*")
        self.assertIn("X-Api-Key", headers["Access-Control-Allow-Headers"])

    def test_options_request_returns_cors_headers(self):
        api_handler = load_api_handler()

        response = api_handler.lambda_handler({
            "httpMethod": "OPTIONS",
            "path": "/urls",
            "headers": {"Origin": "https://dashboard.example.com"},
        }, None)

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(response["headers"]["Access-Control-Allow-Origin"], "https://dashboard.example.com")
        self.assertIn("X-Api-Key", response["headers"]["Access-Control-Allow-Headers"])

    def test_invalid_json_body_returns_400(self):
        api_handler = load_api_handler()

        response = api_handler.lambda_handler({
            "httpMethod": "POST",
            "path": "/urls",
            "body": "{bad-json",
            "headers": {"Origin": "https://dashboard.example.com"},
        }, None)

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("valid JSON", response["body"])

    def test_delete_url_removes_current_status_record(self):
        api_handler = load_api_handler()
        urls_table = FakeTable()
        latest_table = FakeTable()
        api_handler.urls_table = urls_table
        api_handler.latest_status_table = latest_table

        response = api_handler.delete_url("example.com", {})

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(urls_table.deleted_key, {"url": "https://example.com"})
        self.assertEqual(latest_table.deleted_key, {"url": "https://example.com"})

    def test_get_urls_paginates_scan_results(self):
        api_handler = load_api_handler()
        api_handler.urls_table = FakeTable(pages=[
            {
                "Items": [{"url": "https://b.example.com"}],
                "LastEvaluatedKey": {"url": "https://b.example.com"},
            },
            {"Items": [{"url": "https://a.example.com"}]},
        ])

        response = api_handler.get_urls({})
        body = response["body"]

        self.assertEqual(response["statusCode"], 200)
        self.assertIn("https://a.example.com", body)
        self.assertIn("https://b.example.com", body)

    def test_get_status_reads_latest_status_table_only(self):
        api_handler = load_api_handler()
        latest_table = FakeTable()
        checks_table = FakeTable()
        latest_table.items = [{
            "url": "https://example.com",
            "timestamp": "2026-06-12T00:00:00Z",
            "status_code": 200,
            "latency_ms": 50,
            "is_up": True,
        }]
        checks_table.scan = lambda **_kwargs: (_ for _ in ()).throw(
            AssertionError("historical checks table should not be scanned for current status")
        )
        api_handler.latest_status_table = latest_table
        api_handler.checks_table = checks_table

        response = api_handler.get_status({})

        self.assertEqual(response["statusCode"], 200)
        self.assertIn("https://example.com", response["body"])


if __name__ == "__main__":
    unittest.main()
