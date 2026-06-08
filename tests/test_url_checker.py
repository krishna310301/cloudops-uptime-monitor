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
    def __init__(self):
        self.items = []

    def put_item(self, Item):
        self.items.append(Item)


class FakeSnsClient:
    def publish(self, **_kwargs):
        return {"MessageId": "test-message-id"}


def load_url_checker():
    fake_boto3 = types.SimpleNamespace(
        resource=lambda *_args, **_kwargs: FakeDynamoResource(),
        client=lambda *_args, **_kwargs: FakeSnsClient(),
    )

    with patch.dict(sys.modules, {"boto3": fake_boto3}), patch.dict(
        os.environ,
        {"SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test"},
    ):
        return importlib.reload(importlib.import_module("lambda.url_checker"))


class UrlCheckerTests(unittest.TestCase):
    def test_save_to_dynamodb_writes_ttl(self):
        url_checker = load_url_checker()
        table = FakeTable()
        url_checker.checks_table = table
        url_checker.RESULT_TTL_DAYS = 30

        now = int(time.time())
        url_checker.save_to_dynamodb({
            "url": "https://example.com",
            "timestamp": "2026-06-07T00:00:00Z",
            "status_code": 200,
            "latency_ms": 123,
            "is_up": True,
        })

        self.assertGreaterEqual(table.items[0]["ttl"], now + (29 * 24 * 60 * 60))
        self.assertLessEqual(table.items[0]["ttl"], now + (31 * 24 * 60 * 60))


if __name__ == "__main__":
    unittest.main()
