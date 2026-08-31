"""Offline exporter tests. Run: python3 -m unittest discover -s test -p 'test_mp_export.py'."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import tomllib
import unittest
from types import ModuleType, SimpleNamespace
from unittest.mock import MagicMock, Mock, patch
import io
from contextlib import redirect_stderr

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "export_mp_pilot.py"
spec = importlib.util.spec_from_file_location("mp_export", SCRIPT)
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


def document(material_id="mp-1", **changes):
    return dict(material_id=material_id, composition={"Al": 2.0, "Mg": 1, "O": 4},
                theoretical=False, database_IDs={"icsd": ["synthetic"]}, deprecated=False) | changes


class ExportTests(unittest.TestCase):
    def test_external_error_diagnostics_do_not_expose_secrets(self):
        secret = "private-key-that-must-not-be-shown"
        try:
            raise ValueError(f"request failed: x-api-key={secret}; url=https://example.org/?token={secret}")
        except ValueError as error:
            message = exporter.failure_diagnostic(error, "initializing the MP client")
        self.assertIn("initializing the MP client", message)
        self.assertIn("ValueError", message)
        self.assertIn("Code path:", message)
        self.assertNotIn(secret, message)
        self.assertNotIn("example.org", message)
        self.assertNotIn("x-api-key", message)
        error = RuntimeError(secret)
        error.response = SimpleNamespace(status_code=401)
        self.assertIn("MP rejected access (HTTP 401)", exporter.failure_diagnostic(error, "fetching candidate records"))
        self.assertNotIn(secret, exporter.failure_diagnostic(error, "fetching candidate records"))

    def test_cli_reports_initialization_and_record_validation_failures(self):
        fake_client = ModuleType("mp_api.client")
        fake_client.MPRester = MagicMock()
        # This dummy key is only supplied to mocked code; no network access.
        secret = "s" * 32
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"MP_API_KEY": secret}), \
                patch.dict("sys.modules", {"mp_api.client": fake_client}):
            target = Path(tmp) / "snapshot"
            fake_client.MPRester.side_effect = ValueError(secret)
            errors = io.StringIO()
            with redirect_stderr(errors):
                code = exporter.main(["--output", str(target)])
            self.assertEqual(code, 2)
            self.assertIn("failed during initializing the MP client (ValueError)", errors.getvalue())
            self.assertNotIn(secret, errors.getvalue())
            self.assertFalse(target.exists())

            fake_client.MPRester.side_effect = None
            # Source contents must not be printed when a record fails validation.
            bad_docs = [document(database_IDs={"icsd": [secret, 123]})]
            errors = io.StringIO()
            with patch.object(exporter, "fetch_snapshot", return_value=(bad_docs, "test")), \
                    patch.object(exporter.importlib.metadata, "version", return_value="test"), \
                    redirect_stderr(errors):
                code = exporter.main(["--output", str(target)])
            self.assertEqual(code, 2)
            self.assertIn("validating and writing the snapshot", errors.getvalue())
            self.assertIn("Record 1: Malformed source identifiers", errors.getvalue())
            self.assertNotIn(secret, errors.getvalue())
            self.assertFalse(target.exists())

    def test_wrong_length_key_is_explained_without_printing_it(self):
        secret = "incorrect-length-key"
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"MP_API_KEY": secret}):
            errors = io.StringIO()
            with redirect_stderr(errors), self.assertRaises(SystemExit):
                exporter.main(["--output", str(Path(tmp) / "snapshot")])
            self.assertIn("32 characters", errors.getvalue())
            self.assertNotIn(secret, errors.getvalue())

    def test_integer_counts_without_rounding(self):
        self.assertEqual(exporter.integer_formula({"O": 4.0, "Mg": 1, "Al": 2}), ("Al2Mg1O4", "."))
        for counts, reason in [({"Li": 1.5}, "fractional_counts"), ({"O": 0}, "invalid_counts"),
                               ({"O": True}, "invalid_counts"), ({"O": "2"}, "invalid_counts"),
                               ({"Fe2+": 1}, "unsupported_species"), ({"O": float("inf")}, "invalid_counts"),
                               ({"O": 2**63}, "count_overflow"), ({}, "missing_composition")]:
            self.assertEqual(exporter.integer_formula(counts), (".", reason))

    def test_unknown_provenance_stays_unknown(self):
        self.assertEqual(exporter.normalized_row(document(theoretical=None, database_IDs=None))[2:4], ("unknown", "."))
        with self.assertRaises(ValueError):
            exporter.normalized_row(document(theoretical="false"))
        with self.assertRaises(ValueError):
            exporter.normalized_row(document(database_IDs={"icsd": ["bad\nid"]}))

    def test_legacy_and_alphabetic_material_ids(self):
        # Emmet's AlphaID represents legacy mp-149 as mp-aaaaaaft (or mp-ft).
        for material_id in ("mp-149", "mp-aaaaaaft", "mp-ft"):
            with self.subTest(material_id=material_id):
                self.assertEqual(exporter.normalized_row(document(material_id))[0], material_id)
        for material_id in (None, 149, "mp-", "mp-abc123", "mp-FT", "mvc-149",
                            "mp-149-extra", "mp-149\n", "mp-١٤٩"):
            with self.subTest(material_id=material_id):
                with self.assertRaises(exporter.ExportValidationError):
                    exporter.normalized_row(document(material_id))

    def test_snapshot_integrity_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "snapshot"
            docs = [document("mp-aaaaaaft", theoretical=True), document()]
            exporter.write_snapshot(docs, target, database_version="fixture-v1", client_version="test", is_synthetic=True)
            metadata = tomllib.loads((target / "snapshot.toml").read_text())
            self.assertTrue(metadata["is_synthetic"])
            self.assertFalse(metadata["query_include_gnome"])
            self.assertEqual(metadata["record_count"], 2)
            self.assertEqual(metadata["records_sha256"], hashlib.sha256((target / "records.tsv").read_bytes()).hexdigest())
            self.assertEqual(metadata["jsonl_sha256"], hashlib.sha256((target / "records.jsonl").read_bytes()).hexdigest())
            raw = [json.loads(line) for line in (target / "records.jsonl").read_text().splitlines()]
            self.assertEqual([r["material_id"] for r in raw], ["mp-1", "mp-aaaaaaft"])
            rows = (target / "records.tsv").read_text().splitlines()[1:]
            self.assertEqual([row.split("\t")[0] for row in rows], ["mp-1", "mp-aaaaaaft"])
            original = {p.name: p.read_bytes() for p in target.iterdir()}
            with self.assertRaises(ValueError):
                exporter.write_snapshot(docs, target, database_version="fixture-v1", client_version="test")
            self.assertEqual(original, {p.name: p.read_bytes() for p in target.iterdir()})

    def test_bad_data_leaves_no_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "snapshot"
            for docs in ([], [document(), document(theoretical=True)], [document(deprecated=True)],
                         [document(deprecated=None)], [document(material_id="invalid")]):
                with self.assertRaises(ValueError):
                    exporter.write_snapshot(docs, target, database_version="test", client_version="test")
                self.assertFalse(target.exists())
            # Failure after mkdir (JSON rejects NaN) also cleans the owned output.
            with self.assertRaises(ValueError):
                exporter.write_snapshot([document(composition={"O": float("nan")})], target,
                                        database_version="test", client_version="test")
            self.assertFalse(target.exists())

    def test_query_scope_and_release_change(self):
        search = Mock(return_value=[document()])
        heartbeat = Mock()
        heartbeat.json.side_effect = [{"db_version": "v1"}, {"db_version": "v1"}]
        rester = SimpleNamespace(endpoint="https://api.materialsproject.org/", db_version="v1",
                                 session=SimpleNamespace(get=Mock(return_value=heartbeat)),
                                 materials=SimpleNamespace(summary=SimpleNamespace(search=search)))
        docs, version = exporter.fetch_snapshot(rester)
        self.assertEqual(version, "v1")
        self.assertEqual(len(docs), 1)
        self.assertEqual(search.call_args.kwargs["elements"], ["O"])
        self.assertEqual(search.call_args.kwargs["num_elements"], 3)
        self.assertIs(search.call_args.kwargs["num_chunks"], None)
        self.assertFalse(search.call_args.kwargs["include_gnome"])
        self.assertNotIn("theoretical", search.call_args.kwargs)  # Need positives AND unlabelled.
        self.assertNotIn("energy_above_hull", search.call_args.kwargs)
        self.assertEqual(rester.session.get.call_count, 2)
        heartbeat.json.side_effect = [{"db_version": "v1"}, {"db_version": "v2"}]
        with self.assertRaises(ValueError):
            exporter.fetch_snapshot(rester)
        heartbeat.json.side_effect = [{"db_version": "v2"}]
        with self.assertRaises(ValueError):
            exporter.fetch_snapshot(rester)  # Cached client still points to v1.

    def test_key_required_before_dependency_import_or_network(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict("os.environ", {"MP_API_KEY": ""}):
            errors = io.StringIO()
            with redirect_stderr(errors), self.assertRaises(SystemExit) as result:
                exporter.main(["--output", str(Path(tmp) / "snapshot")])
            self.assertEqual(result.exception.code, 2)
            self.assertIn("MP_API_KEY", errors.getvalue())
            self.assertFalse((Path(tmp) / "snapshot").exists())


if __name__ == "__main__":
    unittest.main()
