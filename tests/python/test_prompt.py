"""REQ-SW-DOC-04: prompt structure mandates literal `<section id>` for the 9
required IDs across PART A and PART B."""
from __future__ import annotations

from doc_generator import prompt as P


REQUIRED_PART_A = {"header", "summary", "scope", "mil", "sil", "pil"}
REQUIRED_PART_B = {"header", "analysis", "conclusion"}


def test_part_a_lists_six_section_ids():
    sa = P.SYSTEM_PROMPT_A
    for sid in REQUIRED_PART_A:
        assert f'id="{sid}"' in sa or f"id='{sid}'" in sa, \
            f"PART A system prompt missing id='{sid}'"


def test_part_b_lists_three_section_ids():
    sb = P.SYSTEM_PROMPT_B
    for sid in REQUIRED_PART_B:
        assert f'id="{sid}"' in sb or f"id='{sid}'" in sb, \
            f"PART B system prompt missing id='{sid}'"


def test_part_a_requires_literal_section_tag():
    """The instruction must mention `<section ` so the LLM does not
    emit `<div id="...">` instead."""
    assert "<section" in P.SYSTEM_PROMPT_A
    assert "<section" in P.SYSTEM_PROMPT_B


def test_back_compat_aliases_point_to_part_a():
    assert P.SYSTEM_PROMPT is P.SYSTEM_PROMPT_A
    assert P.USER_PROMPT_TEMPLATE is P.USER_PROMPT_TEMPLATE_A


def test_user_templates_contain_payload_placeholder():
    assert "{payload}" in P.USER_PROMPT_TEMPLATE_A
    assert "{payload}" in P.USER_PROMPT_TEMPLATE_B
