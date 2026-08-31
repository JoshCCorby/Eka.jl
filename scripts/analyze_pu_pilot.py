#!/usr/bin/env python3
"""Validate and summarize a frozen v1 pilot without changing scores or labels.

Python 3.11+ standard library only. Outputs are local, unreviewed derivatives.
The Julia loader establishes original-input provenance before ranking; this
independent check reconstructs membership, ordering, popularity, and metrics.
Similarity scores require the separately recorded exact Julia reproduction.
"""

import argparse
import csv
import hashlib
import json
import math
from collections import Counter
from fractions import Fraction
from pathlib import Path
from statistics import mean, median
import tomllib

METHODS = ("random", "popularity", "similarity")
PROTOCOL_SHA = "f64c1fb803da3cc57aff658341b299824e3d662cc48039586a8bc10410bab21f"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def key(domain, seed, formula):
    return hashlib.sha256(f"eka-pu-{domain}-v1\n{seed}\n{formula}".encode()).hexdigest()


def rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def write_rows(path, data):
    with path.open("x", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(data[0]), delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(data)


def validate(run):
    config = tomllib.loads((run / "config.toml").read_text())
    require(config["protocol_sha256"] == PROTOCOL_SHA, "not the frozen protocol")
    require(config["protocol_id"] in ("eka-mp-recovery-v1", "eka-mp-recovery-synthetic-v1"), "wrong protocol")
    require(config["is_synthetic"] == (config["protocol_id"] == "eka-mp-recovery-synthetic-v1"), "synthetic status mismatch")
    require(config["methods"] == list(METHODS), "wrong methods")
    require(config["tie_seed"] == 20260901, "wrong tie seed")
    seeds, budgets = config["split_seeds"], config["budgets"]
    if not config["is_synthetic"]:
        require(seeds == list(range(20)) and budgets == [20, 50, 100, 200], "incomplete real design")
    require(config["ranking_seeds"] == [10000 + s for s in seeds], "wrong ranking seeds")
    expected = {f"split-{s:02}/{m}.tsv" for s in seeds for m in METHODS} | {"metrics.tsv", "report.md"}
    require(set(config["deterministic_file_hashes"]) == expected, "wrong deterministic file set")
    for name in expected:
        require(sha(run / name) == config["deterministic_file_hashes"][name], f"hash mismatch: {name}")
    actual = {str(p.relative_to(run)) for p in run.glob("split-*/*.tsv")}
    require(actual == expected - {"metrics.tsv", "report.md"}, "unexpected ranking files")
    source_path = run / "inputs/provenance/audit/compositions.tsv"
    require(sha(source_path) == config["input_hashes"]["audit/compositions.tsv"], "source-group hash mismatch")
    source = rows(source_path)
    require(all(r["label"] in ("positive", "unlabelled", "unresolved") for r in source), "unknown source label")
    require(len({r["composition"] for r in source}) == len(source), "duplicate source compositions")
    groups = {r["composition"]: r for r in source}
    positives = {f for f, r in groups.items() if r["label"] == "positive"}
    unlabelled = {f for f, r in groups.items() if r["label"] == "unlabelled"}
    metrics = rows(run / "metrics.tsv")
    expected_keys = {(s, m, k) for s in seeds for m in METHODS for k in budgets}
    indexed = {(int(r["split_seed"]), r["method"], int(r["budget"])): r for r in metrics}
    require(len(metrics) == len(indexed) and set(indexed) == expected_keys, "missing/duplicate metric rows")
    rankings, memberships, ties = {}, {}, []
    for s in seeds:
        heldout = set(sorted(positives, key=lambda f: (key("split", s, f), f))[:len(positives) // 5])
        training, candidates = positives - heldout, unlabelled | heldout
        n, h = len(candidates), len(heldout)
        memberships[s] = training, candidates, heldout
        prefix = run / f"inputs/split-{s:02}"
        for name, population in (("inputs/training.tsv", training), ("inputs/candidates.tsv", candidates), ("evaluation/heldout.tsv", heldout)):
            require([r["composition"] for r in rows(prefix / name)] == sorted(population), f"membership mismatch: {s}/{name}")
        labels = rows(prefix / "evaluation/labels.tsv")
        require([r["composition"] for r in labels] == sorted(candidates), "evaluation membership mismatch")
        for r in labels:
            require(r["label"] == ("positive" if r["composition"] in heldout else "unlabelled"), "evaluation label mismatch")
        frequencies = Counter(e for f in training for e in groups[f]["chemical_system"].split("-"))
        for method in METHODS:
            ranked = rows(run / f"split-{s:02}/{method}.tsv")
            formulas = [r["composition"] for r in ranked]
            require(len(formulas) == n and set(formulas) == candidates, "incomplete/duplicate ranking")
            sort_keys = []
            scores = []
            for i, r in enumerate(ranked, 1):
                f = r["composition"]
                require(int(r["rank"]) == i and r["tie_key"] == key("tie", 20260901, f), "rank/tie mismatch")
                require(r["observed_label"] == ("positive" if f in heldout else "unlabelled"), "ranking label mismatch")
                if method == "random":
                    require(r["score"] == "" and r["random_key"] == key("random", 10000 + s, f), "random key mismatch")
                    sort_keys.append((r["random_key"], r["tie_key"], f))
                else:
                    score = float(r["score"])
                    require(math.isfinite(score) and 0 <= score <= 1 and r["random_key"] == "", "invalid score")
                    if method == "popularity":
                        elements = groups[f]["chemical_system"].split("-")
                        require(score == sum(frequencies[e] for e in elements) / (len(elements) * len(training)), "popularity mismatch")
                    scores.append(score)
                    sort_keys.append((-score, r["tie_key"], f))
            require(sort_keys == sorted(sort_keys), "incorrect rank order")
            rankings[s, method] = formulas
            counts = Counter(scores)
            for k in budgets:
                r = indexed[s, method, k]
                hits = len(set(formulas[:k]) & heldout)
                expectation = Fraction(k * h, n)
                for field, value in {"hits": hits, "candidate_count": n, "heldout_count": h, "ranking_seed": 10000 + s, "tie_seed": 20260901, "random_expected_hits_numerator": expectation.numerator, "random_expected_hits_denominator": expectation.denominator}.items():
                    require(int(r[field]) == value, f"metric mismatch: {s}/{method}/{k}/{field}")
                for field, value in {"observed_label_fraction": hits/k, "heldout_recall": hits/h, "observed_label_enrichment": (hits/k)/(h/n), "random_expected_hits": k*h/n}.items():
                    require(float(r[field]) == value, f"metric mismatch: {s}/{method}/{k}/{field}")
                if scores:
                    ties.append(dict(split_seed=s, method=method, budget=k, distinct_scores=len(counts), largest_tie=max(counts.values()), cutoff_tie_size=counts[scores[k-1]], selected_from_cutoff_tie=sum(x == scores[k-1] for x in scores[:k])))
    return config, groups, indexed, rankings, memberships, ties


def analyze(run, output):
    config, groups, metrics, rankings, memberships, ties = validate(run)
    require(not output.exists(), "refusing to overwrite analysis directory")
    output.mkdir()
    budgets, seeds = config["budgets"], config["split_seeds"]
    paired, summary = [], []
    for k in budgets:
        diffs = []
        for s in seeds:
            hits = {m: int(metrics[s, m, k]["hits"]) for m in METHODS}
            d = hits["similarity"] - hits["popularity"]
            diffs.append(d)
            paired.append(dict(split_seed=s, budget=k, **hits, similarity_minus_popularity=d))
        summary.append(dict(budget=k, random_mean=mean(int(metrics[s, "random", k]["hits"]) for s in seeds), popularity_mean=mean(int(metrics[s, "popularity", k]["hits"]) for s in seeds), similarity_mean=mean(int(metrics[s, "similarity", k]["hits"]) for s in seeds), difference_mean=mean(diffs), difference_median=median(diffs), difference_min=min(diffs), difference_max=max(diffs), positive=sum(d > 0 for d in diffs), zero=diffs.count(0), negative=sum(d < 0 for d in diffs)))
    subgroups = {}
    for f, r in groups.items():
        elements = r["chemical_system"].split("-")
        labels = [("chemical_system", r["chemical_system"])] + [("element", e) for e in elements]
        labels += [("H_containing", str("H" in elements)), ("halogen_containing", str(bool(set(elements) & {"F", "Cl", "Br", "I", "At", "Ts"}))), ("mixed_flags", str(int(r["experimental_records"]) > 0 and int(r["theoretical_records"]) > 0))]
        for label in labels:
            subgroups.setdefault(label, set()).add(f)
    breakdowns = []
    for s in seeds:
        training, candidates, heldout = memberships[s]
        for (kind, group), members in sorted(subgroups.items()):
            for method in METHODS:
                for k in budgets:
                    selected = set(rankings[s, method][:k]) & members
                    denominator = len(heldout & members)
                    hits = len(selected & heldout)
                    breakdowns.append(dict(split_seed=s, method=method, budget=k, kind=kind, group=group, training_count=len(training & members), candidate_count=len(candidates & members), heldout_count=denominator, selected_count=len(selected), hits=hits, heldout_recall=hits/denominator if denominator else "", observed_label_fraction=hits/len(selected) if selected else ""))
    write_rows(output / "paired-differences.tsv", paired)
    write_rows(output / "budget-summary.tsv", summary)
    write_rows(output / "score-ties.tsv", ties)
    write_rows(output / "descriptive-breakdowns.tsv", breakdowns)
    (output / "validation.json").write_text(json.dumps(dict(status="passed", config_sha256=sha(run / "config.toml"), metrics_sha256=sha(run / "metrics.tsv"), metric_rows=len(metrics), rankings=len(rankings), independent_checks="source-group split reconstruction, membership and labels, complete ranking permutations, hash keys, ordering, popularity scores, all metrics and denominators", similarity_check="finite bounded scores and ordering here; exact score recomputation requires separate Julia reproduction"), indent=2) + "\n")
    lines = ["# Frozen v1 recovery pilot", "", "**Local only: redistribution of these data-derived results is not cleared.**", "", "Question: do composition-similarity rankings recover more withheld MP experimental-provenance compositions than training-element popularity within the frozen MP pool?", "", f"Protocol: `{config['protocol_id']}`; hash `{config['protocol_sha256']}`. No label, budget, method, or split changes were made for this analysis.", ""]
    if config["is_synthetic"]:
        lines += ["**Synthetic fixture; not scientific evidence.**", ""]
    t, c, h = memberships[seeds[0]]
    lines += [f"Each split has {len(t):,} training positives, {len(c):,} candidates and {len(h):,} held-out positives ({len(h)/len(c):.4%} observed-positive prevalence). All methods use identical candidate membership within a split.", "", "## Primary paired comparison at k=100", ""]
    primary = next((r for r in summary if r["budget"] == 100), None)
    if primary:
        lines += [f"Similarity minus popularity hits: mean **{primary['difference_mean']:+.2f}**, median **{primary['difference_median']:+.1f}**, range {primary['difference_min']:+d} to {primary['difference_max']:+d}; {primary['positive']} positive, {primary['zero']} zero and {primary['negative']} negative splits.", "", "| Split | Random hits | Popularity hits | Similarity hits | D_s |", "| --- | ---: | ---: | ---: | ---: |"]
        for r in paired:
            if r["budget"] == 100:
                lines.append(f"| {r['split_seed']} | {r['random']} | {r['popularity']} | {r['similarity']} | {r['similarity_minus_popularity']:+d} |")
    else:
        lines += ["This synthetic fixture has no k=100 budget."]
    lines += ["", "## All budgets", "", "Mean hits across declared splits; k=100 is primary, other budgets are secondary.", "", "| k | Random observed | Random expected | Popularity | Similarity | Mean difference | Median difference | + / 0 / − |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"]
    for r in summary:
        lines.append(f"| {r['budget']} | {r['random_mean']:.2f} | {r['budget']*len(h)/len(c):.4f} | {r['popularity_mean']:.2f} | {r['similarity_mean']:.2f} | {r['difference_mean']:+.2f} | {r['difference_median']:+.1f} | {r['positive']} / {r['zero']} / {r['negative']} |")
    mixed = sum(int(r["experimental_records"]) > 0 and int(r["theoretical_records"]) > 0 for r in groups.values())
    lines += ["", "## Descriptive checks and limitations", "", f"The snapshot has {mixed:,} mixed-flag composition groups. They remain positive under the frozen rule. Alternative-label analyses have not been run.", "", "`descriptive-breakdowns.tsv` reports all predefined chemical-system, element, H-containing, halogen-containing and mixed-flag groups for every method, split and budget, including training/candidate/held-out/selected denominators. Element groups overlap; zero-denominator ratios are blank. These are descriptive breakdowns, not subgroup significance tests.", "", "`score-ties.tsv` records exact score-tie sizes and how many cutoff-tied candidates enter each budget. Oxygen contributes a constant 1/3 to popularity: all popularity score variation comes from the frequencies of the two other elements, with the frozen formula hash resolving ties.", "", "Variation across these overlapping holdouts is split sensitivity. No confidence intervals or significance claims are made. The random column includes one declared hash ranking per split; its uniform expectation is analytical, not an additional dataset.", "", "This measures recovery of withheld provenance-labelled compositions under random composition holdout. A positive label is at least one MP record with theoretical=false, not verified synthesis success. Unlabelled candidates are not known failed syntheses. MP coverage, historical research effort, mixed polymorph flags and the representation constrain interpretation. Formula grouping prevents composition leakage but permits shared chemical systems and close analogues between training and candidates. Oxygen-containing ternaries are not an oxidation-state-validated oxide set. These results establish neither chronological discovery nor transfer to unseen element combinations.", "", "## Evidence", "", "`validation.json` records independent validation; `paired-differences.tsv` preserves every split and budget. Full rankings and raw metrics remain in the adjacent results directory. See the parent run's freeze record, reproduction checks and environment instructions for implementation identity and exact-rerun evidence. A valid report does not itself establish upstream authenticity or sharing permission.", ""]
    (output / "report.md").write_text("\n".join(lines))
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(args.run, args.output), indent=2))
