#!/usr/bin/env python3
"""Export an MP oxygen-containing-ternary snapshot for Eka's feasibility audit.

Live access requires the optional mp-api package and an MP API key. The exporter
never writes the key, infers discovery dates, or treats theoretical as negative.
"""

import argparse
import getpass
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shutil
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation


FIELDS = ["material_id", "composition", "formula_pretty", "theoretical",
          "database_IDs", "deprecated"]
HEADER = "material_id\tcomposition\ttheoretical\tsource_ids\tnormalization_issue\n"


class ExportValidationError(ValueError):
    """Exporter-authored messages that contain no credentials or API payloads."""


def failure_diagnostic(error, stage):
    """Identify the failing operation without printing third-party error text/locals."""
    lines = [f"MP export failed during {stage} ({type(error).__name__})."]
    if isinstance(error, ExportValidationError):
        lines.append(str(error))
    else:
        status = getattr(getattr(error, "response", None), "status_code", None)
        if isinstance(status, int) and not isinstance(status, bool):
            if status in (401, 403):
                lines.append(f"MP rejected access (HTTP {status}); check your key and account access.")
            else:
                lines.append(f"HTTP request failed with status {status}.")
        lines.append("External exception text is withheld to protect credentials.")
    # Filenames/function names/line numbers identify the code path; never render
    # the exception's original text, source lines, locals, request URL, or headers.
    frames = []
    trace = error.__traceback__
    while trace is not None:
        code = trace.tb_frame.f_code
        frames.append(f"{Path(code.co_filename).name}:{trace.tb_lineno} ({code.co_name})")
        trace = trace.tb_next
    if frames:
        lines.append("Code path: " + " -> ".join(frames[-5:]))
    lines.append("No usable snapshot was written. You can share these diagnostic lines; do not share your API key.")
    return "\n".join(lines)


def integer_formula(amounts):
    """Accept exact integral counts only; never round occupancies into formulas."""
    if not isinstance(amounts, dict) or not amounts:
        return ".", "missing_composition"
    terms = []
    for symbol, raw in sorted(amounts.items()):
        if not re.fullmatch(r"[A-Z][a-z]?", symbol):
            return ".", "unsupported_species"
        if isinstance(raw, bool) or not isinstance(raw, (int, float)):
            return ".", "invalid_counts"
        try:
            amount = Decimal(str(raw))
        except InvalidOperation:
            return ".", "invalid_counts"
        if not amount.is_finite() or amount <= 0:
            return ".", "invalid_counts"
        if amount != amount.to_integral_value():
            return ".", "fractional_counts"
        if amount > 2**63 - 1:
            return ".", "count_overflow"
        terms.append(f"{symbol}{int(amount)}")
    return "".join(terms), "."


def checked_cell(value):
    value = str(value)
    if not value or any(c in value for c in "\t\r\n"):
        raise ExportValidationError("Invalid empty or multiline TSV field in source data")
    return value


def normalized_row(doc):
    material_id = doc.get("material_id")
    # MP supports both legacy numeric IDs and lowercase alphabetic AlphaIDs.
    # Preserve the source spelling rather than converting between representations.
    if not isinstance(material_id, str) or not re.fullmatch(r"mp-(?:[0-9]+|[a-z]+)", material_id):
        raise ExportValidationError("Unexpected or missing MP material ID; expected mp- followed by digits or lowercase letters")
    formula, issue = integer_formula(doc.get("composition"))
    theoretical = doc.get("theoretical")
    if theoretical is not None and not isinstance(theoretical, bool):
        raise ExportValidationError("Malformed theoretical flag; expected true, false, or null")
    flag = "unknown" if theoretical is None else str(theoretical).lower()
    source_ids = doc.get("database_IDs")
    if source_ids is not None and not isinstance(source_ids, dict):
        raise ExportValidationError("Malformed database_IDs; expected an object or null")
    sources = []
    for source, ids in (source_ids or {}).items():
        if not isinstance(source, str) or not isinstance(ids, list) or not all(isinstance(i, str) for i in ids):
            raise ExportValidationError("Malformed source identifiers; expected each database_IDs value to be a list of strings")
        sources.extend(f"{source}:{entry}" for entry in ids)
    return tuple(map(checked_cell, (material_id, formula, flag,
                                    ";".join(sorted(set(sources))) or ".", issue)))


def write_snapshot(documents, target, *, database_version, client_version, is_synthetic=False):
    """Write all-or-cleanup into a new directory. No overwrite; no model scores."""
    target = Path(target)
    if target.exists() or target.is_symlink():
        raise ExportValidationError("Snapshot output already exists")
    docs = list(documents)
    if not docs:
        raise ExportValidationError("MP returned no records")
    # Check IDs/flags before any filesystem mutation; unexpected data fails closed.
    paired = []
    for index, doc in enumerate(docs, 1):
        if not isinstance(doc, dict):
            raise ExportValidationError(f"Record {index}: expected an API dictionary")
        try:
            paired.append((normalized_row(doc), doc))
        except ExportValidationError as error:
            # Only the ordinal and our fixed validation message are exposed.
            raise ExportValidationError(f"Record {index}: {error}") from None
    paired.sort(key=lambda pair: pair[0][0])
    if len({row[0] for row, _ in paired}) != len(paired):
        raise ExportValidationError("Duplicate material IDs in MP export; retry the export")
    if any(doc.get("deprecated") is not False for _, doc in paired):
        raise ExportValidationError("Deprecated or unspecified status returned despite query filter")
    if not isinstance(database_version, str) or not database_version.strip():
        raise ExportValidationError("MP database version is missing")
    target.mkdir()  # Exclusive: even a dangling symlink/concurrent output must fail.
    try:
        rows_text = HEADER + "".join("\t".join(row) + "\n" for row, _ in paired)
        rows_bytes = rows_text.encode("utf-8")
        (target / "records.tsv").write_bytes(rows_bytes)
        # These are decoded, selected API records, not raw HTTP responses.
        raw_bytes = ("".join(json.dumps(doc, sort_keys=True, ensure_ascii=True,
                                       allow_nan=False) + "\n" for _, doc in paired)).encode()
        (target / "records.jsonl").write_bytes(raw_bytes)
        metadata = {
            "schema_version": 1,
            "dataset": "Materials Project",
            "database_version": database_version,
            "retrieved_at_utc": datetime.now(timezone.utc).isoformat(),
            "endpoint": "https://api.materialsproject.org/materials/summary/",
            "scope": "oxygen-containing ternaries; not oxidation-state-validated oxides",
            "query_elements": ["O"], "query_num_elements": 3,
            "query_deprecated": False, "query_include_gnome": False,
            "fields": FIELDS, "record_count": len(paired),
            "mp_api_version": client_version,
            "python_version": sys.version.split()[0],
            "records_sha256": hashlib.sha256(rows_bytes).hexdigest(),
            "jsonl_sha256": hashlib.sha256(raw_bytes).hexdigest(),
            "exporter_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "normalization": "exact positive integral element counts only; Julia reduces ratios",
            "date_policy": "no first-discovery dates inferred from database timestamps",
            "redistribution_status": "unreviewed; verify applicable terms before publishing",
            "terms_url": "https://materialsproject.org/about/terms",
            "is_synthetic": is_synthetic,
        }
        # These flat metadata values are strings, booleans, integers and string
        # arrays. JSON literals for those types are also valid TOML values.
        text = "".join(f"{key} = {json.dumps(value, ensure_ascii=True)}\n"
                       for key, value in sorted(metadata.items()))
        (target / "snapshot.toml").write_text(text, encoding="utf-8")
    except BaseException:
        shutil.rmtree(target)  # Only the new directory reserved by this call.
        raise
    return target


def live_database_version(rester):
    # Recent mp-api clients cache db_version/get_database_version on construction.
    # Re-read the public heartbeat instead of comparing that cached value twice.
    response = rester.session.get(rester.endpoint.rstrip("/") + "/heartbeat",
                                  headers={"Cache-Control": "no-cache"}, timeout=30)
    response.raise_for_status()
    version = response.json().get("db_version")
    if not isinstance(version, str) or not version.strip():
        raise ExportValidationError("MP heartbeat did not provide a database version")
    return version


def fetch_snapshot(rester, *, progress=None):
    """Reject an export spanning a database release change; fetch all pages."""
    progress = progress or (lambda stage: None)
    progress("initial database-version check")
    before = live_database_version(rester)
    cached_version = getattr(rester, "db_version", before)
    if cached_version is not None and cached_version != before:
        raise ExportValidationError("Client database version differs from live MP; create a new session")
    progress("fetching candidate records")
    documents = rester.materials.summary.search(
        elements=["O"], num_elements=3, deprecated=False, include_gnome=False,
        all_fields=False, fields=FIELDS, num_chunks=None, chunk_size=1000,
    )
    progress("final database-version check")
    after = live_database_version(rester)
    if before != after:
        raise ExportValidationError("MP database changed during export; retry before using the snapshot")
    return documents, before


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path,
                        help="New snapshot directory; parent must exist")
    parser.add_argument("--prompt-key", action="store_true",
                        help="Securely prompt in a local terminal if MP_API_KEY is not set")
    args = parser.parse_args(argv)
    if args.output.exists() or args.output.is_symlink():
        parser.error("output already exists")
    if not args.output.parent.is_dir():
        parser.error("output parent must exist")
    api_key = os.environ.get("MP_API_KEY", "").strip()
    if not api_key and args.prompt_key:
        if not sys.stdin.isatty():
            parser.error("--prompt-key requires an interactive local terminal")
        api_key = getpass.getpass("MP API key (not saved): ").strip()
    if not api_key:
        parser.error("Set MP_API_KEY locally before exporting; never commit or paste the key")
    if len(api_key) != 32:
        parser.error("MP API keys must be 32 characters; enter only the key, without quotes or a variable name")
    stage = "loading the MP client"

    def progress(next_stage):
        nonlocal stage
        stage = next_stage
        print(f"MP export: {stage}...", file=sys.stderr, flush=True)

    try:
        from mp_api.client import MPRester
    except ImportError:
        parser.error("Install scripts/requirements-mp.txt in a separate Python environment")
    except Exception as error:
        print(failure_diagnostic(error, stage), file=sys.stderr)
        return 2
    try:
        progress("initializing the MP client")
        with MPRester(api_key=api_key, use_document_model=False,
                      mute_progress_bars=True) as rester:
            docs, version = fetch_snapshot(rester, progress=progress)
            progress("closing the MP connection")
        progress("validating and writing the snapshot")
        output = write_snapshot(docs, args.output, database_version=version,
                                client_version=importlib.metadata.version("mp-api"))
    except Exception as error:
        print(failure_diagnostic(error, stage), file=sys.stderr)
        return 2
    print(f"Exported {len(docs)} MP records to {output}; redistribution remains unreviewed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
