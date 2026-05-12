"""REQ-SW-DOC-06: llm_client uses an explicit User-Agent and is OpenAI-compatible."""
from __future__ import annotations
import io
import json
from unittest.mock import patch, MagicMock

from doc_generator import llm_client as L


class _FakeResponse:
    def __init__(self, body: bytes):
        self._body = body
    def read(self):
        return self._body
    def __enter__(self):
        return self
    def __exit__(self, *a):
        return False


def _ok_response(text: str = "<p>hi</p>") -> _FakeResponse:
    body = {"choices": [{"message": {"content": text}}]}
    return _FakeResponse(json.dumps(body).encode("utf-8"))


def test_chat_sets_explicit_user_agent_header():
    captured = {}

    def fake_urlopen(req, timeout=600):
        captured["headers"] = dict(req.header_items())
        captured["url"] = req.full_url
        return _ok_response()

    with patch.object(L.urllib.request, "urlopen", side_effect=fake_urlopen):
        out = L.chat("k", "sys", "user")
    assert out == "<p>hi</p>"
    # urllib normalises header-name casing to "Title-Case".
    assert captured["headers"].get("User-agent") == \
        "bms-engineering-assistant/1.0"
    assert captured["headers"].get("Authorization") == "Bearer k"


def test_chat_sends_both_max_tokens_keys():
    captured = {}

    def fake_urlopen(req, timeout=600):
        captured["body"] = json.loads(req.data.decode("utf-8"))
        return _ok_response()

    with patch.object(L.urllib.request, "urlopen", side_effect=fake_urlopen):
        L.chat("k", "s", "u", max_completion_tokens=1234)
    assert captured["body"]["max_tokens"] == 1234
    assert captured["body"]["max_completion_tokens"] == 1234
    # gpt-oss reasoning cap.
    assert captured["body"]["reasoning_effort"] == "low"


def test_chat_retries_on_429_then_succeeds():
    import urllib.error
    calls = {"n": 0}

    def fake_urlopen(req, timeout=600):
        calls["n"] += 1
        if calls["n"] == 1:
            err = urllib.error.HTTPError(
                req.full_url, 429, "rate_limit", {},
                io.BytesIO(b'{"error":"rate_limit_exceeded"}'))
            raise err
        return _ok_response("<p>retry-ok</p>")

    with patch.object(L.urllib.request, "urlopen", side_effect=fake_urlopen), \
         patch.object(L.time, "sleep"):
        out = L.chat("k", "s", "u",
                     rate_limit_retries=1, rate_limit_wait_s=0)
    assert out == "<p>retry-ok</p>"
    assert calls["n"] == 2
