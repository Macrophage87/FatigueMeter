"""Provenance & honesty parsing (scientific-validation-prompt.md §4).

Parses the repository's own honesty surfaces — docs/traceability.md,
resources/properties.xml, resources/settings/settings.xml,
resources/strings/strings.xml — so the harness can enforce:
  * convention/synthesis values are live SETTINGS, not hard-coded;
  * shipped defaults agree with the ported code defaults;
  * status/advisory copy is descriptive MOOD (no imperative verbs);
  * every code constant has a traceability row.

All parsers degrade gracefully (return None / empty) when a file is absent, so
the harness still runs when it sits on a branch without the app resources.
"""
from __future__ import annotations

import os
import re
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional


def repo_root() -> Optional[str]:
    """Walk up from this file looking for the FatigueMeter repo root (a dir that
    has docs/white-paper.md)."""
    here = os.path.abspath(os.path.dirname(__file__))
    d = here
    for _ in range(6):
        if os.path.exists(os.path.join(d, "docs", "white-paper.md")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return None


def _path(*parts) -> Optional[str]:
    root = repo_root()
    if root is None:
        return None
    p = os.path.join(root, *parts)
    return p if os.path.exists(p) else None


def parse_properties() -> Optional[Dict[str, str]]:
    """resources/properties/properties.xml -> {id: default_string}."""
    p = _path("resources", "properties", "properties.xml")
    if p is None:
        return None
    tree = ET.parse(p)
    out = {}
    for prop in tree.getroot().findall("property"):
        pid = prop.get("id")
        if pid:
            out[pid] = (prop.text or "").strip()
    return out


def parse_settings_keys() -> Optional[List[str]]:
    """propertyKeys referenced by resources/settings/settings.xml."""
    p = _path("resources", "settings", "settings.xml")
    if p is None:
        return None
    text = open(p, encoding="utf-8").read()
    return re.findall(r"@Properties\.(\w+)", text)


def parse_strings() -> Optional[Dict[str, str]]:
    """resources/strings/strings.xml -> {id: text}."""
    p = _path("resources", "strings", "strings.xml")
    if p is None:
        return None
    tree = ET.parse(p)
    out = {}
    for s in tree.getroot().findall("string"):
        sid = s.get("id")
        if sid:
            out[sid] = (s.text or "").strip()
    return out


def parse_traceability_symbols() -> Optional[List[str]]:
    """First-column code symbols of docs/traceability.md's table."""
    p = _path("docs", "traceability.md")
    if p is None:
        return None
    syms = []
    for line in open(p, encoding="utf-8"):
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if not cells:
            continue
        first = cells[0]
        # skip header / separator rows
        if first in ("Code symbol", "Threshold") or set(first) <= set("-: "):
            continue
        for tok in re.findall(r"`([^`]+)`", first):
            syms.append(tok)
    return syms


# ---------------------------------------------------------------------------
# Imperative-mood detection (check MOOD, not a substring blacklist)
# ---------------------------------------------------------------------------
# Directive verbs that, when a clause STARTS with them (no subject), signal the
# imperative mood. Heuristic — sufficient for the short, controlled UI copy; a
# fuller check would use POS tagging.
IMPERATIVE_VERBS = {
    "turn", "stop", "ease", "back", "slow", "push", "go", "keep", "avoid",
    "reduce", "increase", "hold", "rest", "recover", "cool", "drink", "eat",
    "quit", "abort", "halt", "decrease", "maintain", "continue", "watch",
    "dig", "attack", "empty", "save", "pace", "settle", "relax", "breathe",
    "pull", "finish", "sprint", "surge", "accelerate", "brake", "sit",
}
DIRECTIVE_PHRASES = [
    "turn back", "ease off", "back off", "slow down", "dig deep", "hold on",
    "ease soon", "back down", "cool down", "keep going",
]


def _first_word(s: str) -> str:
    # strip leading emoji / symbols / punctuation
    cleaned = re.sub(r"^[^A-Za-z]+", "", s.strip())
    m = re.match(r"[A-Za-z']+", cleaned)
    return m.group(0).lower() if m else ""


def is_imperative(text: str) -> bool:
    low = text.lower()
    for phrase in DIRECTIVE_PHRASES:
        if phrase in low:
            return True
    # check each clause (split on '/', '·', '.', ',') for an imperative-mood start
    for clause in re.split(r"[/·.,;]", text):
        w = _first_word(clause)
        if w in IMPERATIVE_VERBS:
            return True
    return False


# UI copy that is USER-FACING STATUS / ADVISORY (must be descriptive). Other
# strings (setting labels like "AFI fresh cutoff") are not verdict copy.
STATUS_STRING_IDS = [
    "StateFresh", "StateBuilding", "StateDrifting", "StateNoData",
    "RedFeat", "RedAttrition", "AdvisoryTag", "UncalibratedTag",
    "DecoupOnlyTag", "BucketFresh", "BucketModerate", "BucketHeavy",
]
