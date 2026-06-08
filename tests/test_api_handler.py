import importlib
import sys
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

    def delete_item(self, Key):
        self.deleted_key = Key

    def scan(self, **_kwargs):
        return {"Items": self.items}


def load_api_handler():
    fake_boto3 = types.SimpleNamespace(resource=lambda *_args, **_kwargs: FakeDynamoResource())
    with patch.dict(sys.modules, {"boto3": fake_boto3}):
        return importlib.reload(importlib.import_module("lambda.api_handler"))


class ApiHandlerTests(unittest.TestCase):
    def test_normalize_url_adds_https(self):
        api_handler = load_api_handler()

        self.assertEqual(api_handler.normalize_url("example.com"), "https://example.com")

    def test_is_valid_url_rejects_non_http(self):
        api_handler = load_api_handler()

        self.assertFalse(api_handler.is_valid_url("ftp://example.com"))
        self.assertTrue(api_handler.is_valid_url("https://example.com"))

    def test_add_url_stores_normalized_url(self):
        api_handler = load_api_handler()
        table = FakeTable()
        api_handler.urls_table = table

        response = api_handler.add_url("example.com", {})

        self.assertEqual(response["statusCode"], 201)
        self.assertEqual(table.items, [{"url": "https://example.com"}])


if __name__ == "__main__":
    unittest.main()
