#!/usr/bin/env python3
"""Read-only coverage inspection for an external composition-score database.

This answers one question for the Day 4 eligibility gate in
docs/mp-external-score-provenance.md: which audited MP composition groups carry
an external score, broken down by PU label. Coverage must be inspected before
any performance number is read, so this script deliberately computes no ranking,
no hit count, and no metric.

It opens the score database read-only and never writes to it. The audited
composition file and the score database both stay outside Git; only the
aggregate counts printed here are quoted in the tracked review.

    python3 scripts/inspect_external_scores.py \\
        --scores /path/to/recommender-2024-07-01.sqlite \\
        --audit reports/local/mp-ternary-audit/compositions.tsv
"""

import argparse
import hashlib
import sqlite3
from collections import Counter
from functools import reduce
from math import gcd

LABELS = ("positive", "unlabelled", "unresolved")


def canonical(pairs):
    """Reduced, alphabetically sorted formula with explicit ones, as in Eka's Composition."""
    counts = {}
    for symbol, amount in pairs:
        amount = int(amount)
        if amount <= 0:
            raise ValueError(f"nonpositive amount for {symbol}")
        counts[symbol] = counts.get(symbol, 0) + amount
    divisor = reduce(gcd, counts.values())
    return "".join(f"{symbol}{counts[symbol] // divisor}" for symbol in sorted(counts))


def read_audit(path):
    groups = {}
    with open(path, encoding="utf-8") as handle:
        header = next(handle).rstrip("\n").split("\t")
        if header[:3] != ["composition", "chemical_system", "label"]:
            raise ValueError(f"unexpected audit header: {header[:3]}")
        for line in handle:
            row = line.rstrip("\n").split("\t")
            formula, label = canonical_formula(row[0]), row[2]
            if label not in LABELS:
                raise ValueError(f"unexpected label: {label}")
            if formula in groups:
                raise ValueError(f"duplicate canonical audited composition: {formula}")
            groups[formula] = label
    return groups


def canonical_formula(text):
    pairs, symbol, digits = [], "", ""
    for character in text:
        if character.isupper():
            if symbol:
                pairs.append((symbol, int(digits) if digits else 1))
            symbol, digits = character, ""
        elif character.islower():
            symbol += character
        elif character.isdigit():
            digits += character
        else:
            raise ValueError(f"unsupported formula character in {text!r}")
    if not symbol:
        raise ValueError(f"empty formula: {text!r}")
    pairs.append((symbol, int(digits) if digits else 1))
    return canonical(pairs)


def read_scores(path, element="O", table="data3"):
    """Distinct canonical scored ternaries containing `element`, with duplicate detection."""
    scores, duplicates, rows, in_scope = {}, 0, 0, 0
    uri = f"file:{path}?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    try:
        query = f"select ele1, ele2, ele3, int1, int2, int3, score from {table}"
        for e1, e2, e3, i1, i2, i3, score in connection.execute(query):
            rows += 1
            if element not in (e1, e2, e3) or len({e1, e2, e3}) != 3:
                continue
            in_scope += 1
            formula = canonical(((e1, i1), (e2, i2), (e3, i3)))
            if formula in scores:
                duplicates += 1
            scores.setdefault(formula, []).append(float(score))
    finally:
        connection.close()
    return scores, rows, in_scope, duplicates


def digest(path, chunk=1 << 20):
    sha = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(chunk), b""):
            sha.update(block)
    return sha.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scores", required=True, help="External score SQLite database (opened read-only)")
    parser.add_argument("--audit", required=True, help="Audited compositions.tsv from eka audit-mp")
    parser.add_argument("--table", default="data3")
    parser.add_argument("--element", default="O")
    arguments = parser.parse_args()

    groups = read_audit(arguments.audit)
    scores, rows, in_scope, duplicates = read_scores(arguments.scores, arguments.element, arguments.table)

    print(f"score database: {arguments.scores}")
    print(f"score database sha256: {digest(arguments.scores)}")
    print(f"audited composition groups: {len(groups)} {dict(Counter(groups.values()))}")
    print(f"{arguments.table} rows: {rows}; distinct-element {arguments.element}-containing ternary rows: {in_scope}")
    print(f"distinct canonical scored compositions in scope: {len(scores)}; duplicate canonical score rows: {duplicates}")

    covered, total = Counter(), Counter()
    for formula, label in groups.items():
        total[label] += 1
        if formula in scores:
            covered[label] += 1
    print("coverage of the audited pool, by label:")
    for label in LABELS:
        if total[label]:
            share = 100 * covered[label] / total[label]
            print(f"  {label}: {covered[label]}/{total[label]} = {share:.2f}%")
    print(f"  all labels: {sum(covered.values())}/{sum(total.values())}")
    if scores:
        overlap = 100 * sum(covered.values()) / len(scores)
        print(f"scored compositions that appear in the audited pool: {overlap:.2f}%")
    values = [value for group in scores.values() for value in group]
    if values:
        print(f"score range in scope: {min(values)} to {max(values)} (uncalibrated; not a probability)")
    print("Coverage only. No ranking, hit count, or recovery metric is computed here.")


if __name__ == "__main__":
    main()
