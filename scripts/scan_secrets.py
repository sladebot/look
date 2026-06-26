#!/usr/bin/env python3
"""Lightweight secret scanner for the Look repository.

This intentionally focuses on high-confidence credential formats so CI catches
real leaks without blocking docs that mention GitHub secret variable names.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

EXCLUDED_DIRS = {
    ".git",
    ".conda",
    ".venv",
    "__pycache__",
    "ios/build",
    "xcuserdata",
}

EXCLUDED_SUFFIXES = {
    ".db",
    ".jpg",
    ".jpeg",
    ".png",
    ".heic",
    ".heif",
    ".arw",
    ".cr2",
    ".nef",
    ".dng",
    ".appiconset",
}

SECRET_PATTERNS = {
    "AWS access key": re.compile(r"\bA[KS]IA[0-9A-Z]{16}\b"),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    "GitHub token": re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{30,}\b"),
    "GitHub fine-grained token": re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    "OpenAI API key": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    "Slack token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"),
    "Private key block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
}


def is_excluded(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    rel_text = rel.as_posix()
    parts = set(rel.parts)

    if parts & EXCLUDED_DIRS:
        return True
    if any(rel_text.startswith(prefix + "/") for prefix in EXCLUDED_DIRS):
        return True
    return path.suffix.lower() in EXCLUDED_SUFFIXES


def iter_files() -> list[Path]:
    return [
        path
        for path in ROOT.rglob("*")
        if path.is_file() and not is_excluded(path)
    ]


def main() -> int:
    findings: list[str] = []

    for path in iter_files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        rel = path.relative_to(ROOT)
        for name, pattern in SECRET_PATTERNS.items():
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{rel}:{line}: potential {name}")

    if findings:
        print("Potential secrets detected:")
        for finding in findings:
            print(f"  {finding}")
        return 1

    print("No high-confidence secrets detected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
