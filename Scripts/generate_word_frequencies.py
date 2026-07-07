#!/usr/bin/env python3
"""Generate the bundled word-frequency dictionary for YubiKeyboard.

The preferred source is the Python `wordfreq` package. Install it locally with:

    python3 -m pip install wordfreq

The generated JSON is intentionally ignored by git. It is a build artifact that
gets bundled into the keyboard extension.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

WORD_RE = re.compile(r"^[a-z][a-z']{1,23}$")
DEFAULT_LIMIT = 30_000

FALLBACK_WORDS = [
    "the", "and", "you", "that", "this", "with", "for", "not", "was", "are",
    "about", "actually", "after", "again", "also", "always", "another", "anything",
    "around", "because", "before", "being", "better", "between", "business", "calling",
    "coming", "could", "delete", "different", "digital", "does", "doing", "done",
    "enough", "every", "especially", "family", "first", "friend", "from", "getting",
    "going", "good", "great", "happy", "have", "hello", "house", "keyboard", "layout",
    "letter", "little", "maybe", "message", "might", "money", "needs", "never",
    "nothing", "people", "phone", "please", "position", "pretty", "probably", "really",
    "right", "should", "something", "space", "still", "testing", "thanks", "their",
    "there", "these", "thing", "think", "those", "through", "today", "tomorrow",
    "tonight", "typing", "using", "watching", "where", "which", "while", "would",
    "wrong", "yesterday", "appointment", "doctor", "meeting", "dinner", "lunch",
    "morning", "weekend",
]


def normalized_score(rank: int, total: int) -> float:
    return round((total - rank) / total, 6)


def fallback_frequencies() -> dict[str, float]:
    total = len(FALLBACK_WORDS)
    return {word: normalized_score(index, total) for index, word in enumerate(FALLBACK_WORDS)}


def wordfreq_frequencies(limit: int) -> dict[str, float]:
    try:
        from wordfreq import top_n_list, zipf_frequency
    except ImportError:
        print(
            "warning: Python package 'wordfreq' is not installed; "
            "using the small fallback dictionary. Install with: python3 -m pip install wordfreq",
            file=sys.stderr,
        )
        return fallback_frequencies()

    frequencies: dict[str, float] = {}
    for word in top_n_list("en", limit * 2, ascii_only=True):
        normalized = word.lower()
        if not WORD_RE.match(normalized):
            continue

        # zipf_frequency is roughly 0-8. Normalize to 0-1 for compact ranking.
        frequencies[normalized] = round(max(zipf_frequency(normalized, "en"), 0.0) / 8.0, 6)
        if len(frequencies) >= limit:
            break

    return frequencies or fallback_frequencies()


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: generate_word_frequencies.py OUTPUT_JSON [LIMIT]", file=sys.stderr)
        return 2

    output_path = Path(sys.argv[1])
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_LIMIT
    frequencies = wordfreq_frequencies(limit)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(frequencies, ensure_ascii=True, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"Generated {len(frequencies)} word frequencies at {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
