#!/usr/bin/env python3
"""Audit an Eka source tree or Git archive before public packaging."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
from typing import Iterable


FORBIDDEN_ROOTS = {"bot", "data", "logs", "reports"}
FORBIDDEN_NAMES = {".env", "Manifest.toml"}
FORBIDDEN_SUFFIXES = {".jsonl", ".sqlite", ".sqlite3", ".db"}
BINARY_ALLOWLIST = {"test/fixtures/tiny_test.db"}
REQUIRED_FILES = {
    "CHANGELOG.md",
    "CITATION.cff",
    "LICENSE",
    "README.md",
    "THIRD_PARTY_NOTICES.md",
}

SECRET_PATTERNS = {
    "private key": re.compile(rb"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    "GitHub token": re.compile(rb"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
    "AWS access key": re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    "literal MP API key": re.compile(
        rb"MP_API_KEY\s*=\s*['\"][A-Za-z0-9]{32}['\"]", re.IGNORECASE
    ),
}
HOME_PATH = re.compile(
    rb"(?:/" + rb"Users/[^/\s]+|/" + rb"home/[^/\s]+)(?:/[^\s'\"`]+)?"
)


def normalize_path(name: str) -> str:
    return PurePosixPath(name).as_posix()


def tracked_entries(root: Path) -> dict[str, bytes]:
    names = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root,
        check=True,
        capture_output=True,
    ).stdout.split(b"\0")
    candidates = [name.decode() for name in names if name]
    attributes = subprocess.run(
        ["git", "check-attr", "-z", "--stdin", "export-ignore"],
        cwd=root,
        check=True,
        input=b"\0".join(name.encode() for name in candidates) + b"\0",
        capture_output=True,
    ).stdout.split(b"\0")
    ignored = {
        attributes[index].decode()
        for index in range(0, len(attributes) - 2, 3)
        if attributes[index + 2] == b"set"
    }
    return {
        name: (root / name).read_bytes()
        for name in candidates
        if name not in ignored and (root / name).is_file()
    }


def archive_entries(root: Path, treeish: str) -> dict[str, bytes]:
    archive = subprocess.run(
        ["git", "archive", "--format=tar", treeish],
        cwd=root,
        check=True,
        capture_output=True,
    ).stdout
    entries: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as tar:
        for member in tar.getmembers():
            if member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                entries[normalize_path(member.name)] = extracted.read()
    return entries


def audit_entries(entries: dict[str, bytes], require_metadata: bool = True) -> dict:
    problems: list[str] = []
    files: list[dict[str, object]] = []
    normalized = {normalize_path(name): body for name, body in entries.items()}

    if require_metadata:
        for name in sorted(REQUIRED_FILES - normalized.keys()):
            problems.append(f"missing required release metadata: {name}")

    for name in sorted(normalized):
        body = normalized[name]
        path = PurePosixPath(name)
        if not path.parts or ".." in path.parts or path.is_absolute():
            problems.append(f"unsafe path: {name}")
            continue
        if path.parts[0] in FORBIDDEN_ROOTS:
            problems.append(f"forbidden release directory: {name}")
        if path.name in FORBIDDEN_NAMES or path.name.startswith(".env."):
            problems.append(f"forbidden release file: {name}")
        if path.suffix.lower() in FORBIDDEN_SUFFIXES and name not in BINARY_ALLOWLIST:
            problems.append(f"unreviewed data/database file: {name}")
        if len(body) > 2_000_000:
            problems.append(f"file exceeds 2 MB review limit: {name}")
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(body):
                problems.append(f"possible {label} in {name}")
        if HOME_PATH.search(body):
            problems.append(f"machine-specific home path in {name}")
        files.append(
            {"path": name, "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest()}
        )

    readme = normalized.get("README.md", b"")
    notices = normalized.get("THIRD_PARTY_NOTICES.md", b"")
    if require_metadata and b"Materials Project" not in readme:
        problems.append("README lacks Materials Project attribution")
    if require_metadata and b"Seko" not in notices:
        problems.append("third-party notices lack Seko attribution")

    manifest_bytes = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {
        "status": "pass" if not problems else "fail",
        "file_count": len(files),
        "total_bytes": sum(int(item["bytes"]) for item in files),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "problems": problems,
        "files": files,
    }


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--archive", metavar="TREEISH", help="audit `git archive` output")
    source.add_argument("--worktree", action="store_true", help="audit tracked worktree files")
    parser.add_argument("--output", type=Path, help="write the JSON manifest here")
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    entries = archive_entries(root, args.archive) if args.archive else tracked_entries(root)
    result = audit_entries(entries)
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    summary = {
        key: result[key]
        for key in ("status", "file_count", "total_bytes", "manifest_sha256", "problems")
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
