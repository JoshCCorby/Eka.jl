#!/usr/bin/env python3
"""Create a tiny, explicitly synthetic recovery snapshot. No MP client or API key.

Formulas and provenance flags are arbitrary software fixtures, not chemistry claims.
Usage: python3 examples/mp_recovery/make_snapshot.py NEW_SNAPSHOT_DIRECTORY
"""
import argparse
import importlib.util
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[2] / "scripts" / "export_mp_pilot.py"
    spec = importlib.util.spec_from_file_location("mp_export", path)
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)
    docs = []

    def add(counts, flag):
        material_id = f"mp-{len(docs) + 1}"
        docs.append(dict(material_id=material_id, composition=counts,
                         formula_pretty="synthetic", theoretical=flag,
                         database_IDs={"icsd": ["synthetic"]} if flag is False else {},
                         deprecated=False))

    for i in range(1, 11):
        add({"Li": i, "Na": 1, "O": 1}, False)
    add({"Li": 2, "Na": 2, "O": 2}, True)  # Same composition; mixed provenance.
    add({"Mg": 1, "Al": 2, "O": 4}, True)
    add({"Ca": 1, "Ti": 1, "O": 3}, True)
    add({"Ba": 1, "Ti": 1, "O": 3}, None)  # Unresolved group; never a negative.
    add({"Ba": 2, "Ti": 2, "O": 6}, True)
    exporter.write_snapshot(docs, args.output, database_version="synthetic-recovery-v1",
                            client_version="not-used-offline", is_synthetic=True)
    print(f"Created synthetic snapshot: {args.output}")


if __name__ == "__main__":
    main()
