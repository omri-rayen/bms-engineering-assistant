"""Minimal OpenAI-compatible chat-completions client (stdlib only).

Provider is selected by env vars so we can swap WisGate / Groq / OpenAI
without touching code:

    LLM_API_URL    full chat-completions endpoint
    LLM_MODEL      model name to send in the payload
    LLM_API_KEY    Bearer token

A single positional fallback (e.g. an explicit `--api-key`) is also
honoured via the `chat()` argument list. Defaults target WisGate +
DeepSeek V4 Flash because that is the high-context provider this
project standardised on.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request


DEFAULT_URL   = os.environ.get("LLM_API_URL",
                               "https://api.groq.com/openai/v1/chat/completions")
DEFAULT_MODEL = os.environ.get("LLM_MODEL", "openai/gpt-oss-120b")


def chat(api_key: str, system_prompt: str, user_prompt: str,
         model: str | None = None,
         url: str | None = None,
         temperature: float = 0.2,
         max_completion_tokens: int = 5000,
         timeout: int = 600,
         rate_limit_retries: int = 1,
         rate_limit_wait_s: int = 30) -> str:
    url   = url   or DEFAULT_URL
    model = model or DEFAULT_MODEL

    payload = {
        "model":       model,
        "temperature": temperature,
        # OpenAI-compatible servers accept either name; send both so the
        # client works against Groq, WisGate, OpenAI and OpenRouter.
        "max_tokens":              max_completion_tokens,
        "max_completion_tokens":   max_completion_tokens,
        # Reasoning models (gpt-oss-*, deepseek-v4-*) consume hidden
        # reasoning tokens out of the same output budget. Capping that to
        # "low" leaves the visible HTML enough room to actually finish.
        "reasoning_effort": "low",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": user_prompt},
        ],
    }
    data = json.dumps(payload).encode("utf-8")

    attempts = rate_limit_retries + 1
    for attempt in range(1, attempts + 1):
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type":  "application/json",
                # Some gateways (Cloudflare in front of api.groq.com) reject
                # the default Python-urllib UA. Sending a real one is
                # harmless on every other provider.
                "User-Agent":    "bms-engineering-assistant/1.0",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read().decode("utf-8")
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")
            transient = e.code in (429, 500, 502, 503, 504) or \
                "rate_limit" in detail.lower()
            if transient and attempt < attempts:
                print(f"[llm] HTTP {e.code} on attempt {attempt}, "
                      f"sleeping {rate_limit_wait_s}s and retrying ...")
                time.sleep(rate_limit_wait_s)
                continue
            raise RuntimeError(f"LLM HTTP {e.code} ({url}): {detail}") from None
        except urllib.error.URLError as e:
            # Connection reset / DNS / TLS hiccups -- treat as transient.
            if attempt < attempts:
                print(f"[llm] URLError {e.reason!r} on attempt {attempt}, "
                      f"sleeping {rate_limit_wait_s}s and retrying ...")
                time.sleep(rate_limit_wait_s)
                continue
            raise RuntimeError(f"LLM URLError ({url}): {e.reason}") from None

    obj = json.loads(body)
    try:
        return obj["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        raise RuntimeError(f"Unexpected LLM response: {body[:500]}")
