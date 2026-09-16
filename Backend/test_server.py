import os
import unittest
from unittest.mock import patch

import server


class FetchPortTests(unittest.TestCase):
    def test_uses_render_port_when_memedrop_port_is_missing(self):
        with patch.dict(os.environ, {"PORT": "10000"}, clear=True):
            self.assertEqual(server.fetch_port(), 10000)

    def test_memedrop_port_takes_precedence(self):
        with patch.dict(
            os.environ,
            {"PORT": "10000", "MEMEDROP_FETCH_PORT": "8080"},
            clear=True,
        ):
            self.assertEqual(server.fetch_port(), 8080)

    def test_defaults_to_8080(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(server.fetch_port(), 8080)


class AuthorizationTests(unittest.TestCase):
    def test_allows_requests_when_api_key_is_not_configured(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertTrue(server.request_is_authorized(None))

    def test_requires_matching_bearer_token(self):
        with patch.dict(os.environ, {"MEMEDROP_API_KEY": "secret"}, clear=True):
            self.assertTrue(server.request_is_authorized("Bearer secret"))
            self.assertFalse(server.request_is_authorized("Bearer wrong"))
            self.assertFalse(server.request_is_authorized(None))


if __name__ == "__main__":
    unittest.main()
