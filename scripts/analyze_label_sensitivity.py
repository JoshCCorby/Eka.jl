#!/usr/bin/env python3
"""Independently validate and summarize the frozen label-sensitivity branches."""

import argparse
import json
import math
from collections import Counter
from fractions import Fraction
from pathlib import Path
from statistics import mean, median
import tomllib

from analyze_pu_pilot import key, require, rows, sha, write_rows

MODES = ("evaluation_only", "full_pipeline")
POLICIES = ("original", "exclude_mixed", "unlabel_mixed")
METHODS = ("random", "popularity", "similarity")
PROTOCOL_SHA = "f577444465292b6f1099e2650eec22106aebfb2ce3b970b86a5a037bc578a09f"


def validate(run):
    config = tomllib.loads((run / "config.toml").read_text())
    require(config["protocol_id"] == "eka-mp-label-sensitivity-v1" and config["protocol_sha256"] == PROTOCOL_SHA, "wrong sensitivity protocol")
    require(sha(run / "protocol.md") == PROTOCOL_SHA, "altered protocol")
    require(config["modes"] == list(MODES) and config["policies"] == list(POLICIES) and config["methods"] == list(METHODS), "incorrect branches")
    seeds, budgets = config["split_seeds"], config["budgets"]
    require(config["tie_seed"] == 20260901 and config["ranking_seeds"] == [s+10000 for s in seeds], "wrong seeds")
    if not config["is_synthetic"]:
        require(seeds == list(range(20)) and budgets == [20,50,100,200], "incomplete real design")
    actual = {str(p.relative_to(run)) for p in run.rglob("*") if p.is_file()} - {"config.toml", "runtime.tsv"}
    require(actual == set(config["deterministic_file_hashes"]), "wrong file inventory")
    for name, digest in config["deterministic_file_hashes"].items():
        require(not Path(name).is_absolute() and ".." not in Path(name).parts, "unsafe inventory path")
        require(sha(run / name) == digest, f"hash mismatch: {name}")
    source = run / "source/audit/compositions.tsv"
    require(sha(source) == config["input_hashes"]["audit/compositions.tsv"], "source hash mismatch")
    require(sha(run / "baseline/config.toml") == config["original_pilot_config_sha256"], "baseline identity mismatch")
    base_config = tomllib.loads((run / "baseline/config.toml").read_text())
    for name, digest in base_config["deterministic_file_hashes"].items():
        require(not Path(name).is_absolute() and ".." not in Path(name).parts, "unsafe baseline path")
        require(sha(run / "baseline" / name) == digest, "captured baseline hash mismatch")
    source_rows = rows(source)
    groups = {r["composition"]: r for r in source_rows}
    require(len(groups) == len(source_rows), "duplicate source composition")
    p = {f for f,r in groups.items() if r["label"] == "positive"}
    u = {f for f,r in groups.items() if r["label"] == "unlabelled"}
    unresolved = set(groups) - p - u
    mixed = {f for f,r in groups.items() if int(r["experimental_records"]) > 0 and int(r["theoretical_records"]) > 0}
    require(mixed <= p and len(mixed) == config["mixed_group_count"], "mixed group mismatch")
    raw_metrics = rows(run / "metrics.tsv")
    index = {(r["mode"], r["policy"], int(r["split_seed"]), r["method"], int(r["budget"])): r for r in raw_metrics}
    expected = {(mode,policy,s,m,k) for mode in MODES for policy in POLICIES for s in seeds for m in METHODS for k in budgets}
    require(len(raw_metrics) == len(index) and set(index) == expected, "incomplete/duplicate metric grid")
    populations = []
    common_rankings = {}
    for mode in MODES:
        for policy in POLICIES:
            eligible_p = p if policy == "original" else p - mixed
            eligible_u = u | mixed if policy == "unlabel_mixed" else u
            for s in seeds:
                original_h = set(sorted(p, key=lambda f:(key("split",s,f),f))[:len(p)//5])
                if mode == "full_pipeline":
                    heldout = set(sorted(eligible_p, key=lambda f:(key("split",s,f),f))[:len(eligible_p)//5])
                    training, candidates = eligible_p - heldout, eligible_u | heldout
                else:
                    training = p - original_h
                    heldout = original_h if policy == "original" else original_h - mixed
                    candidates = u | original_h
                    if policy == "exclude_mixed":
                        candidates -= mixed
                n,h = len(candidates),len(heldout)
                require(h and training and n > h and max(budgets) <= n, "invalid population")
                folder = run / mode / policy / f"split-{s:02}"
                for name,members in (("inputs/training.tsv",training),("inputs/candidates.tsv",candidates),("evaluation/heldout.tsv",heldout)):
                    require([r["composition"] for r in rows(folder/name)] == sorted(members), "membership mismatch")
                labels = rows(folder / "evaluation/labels.tsv")
                require([r["composition"] for r in labels] == sorted(candidates), "label membership mismatch")
                require(all(r["label"] == ("positive" if r["composition"] in heldout else "unlabelled") for r in labels), "label mismatch")
                population = dict(mode=mode,policy=policy,split_seed=s,training_count=len(training),candidate_count=n,heldout_count=h,prevalence=h/n,mixed_training_count=len(training & mixed),mixed_candidate_count=len(candidates & mixed))
                populations.append(population)
                frequencies = Counter(e for f in training for e in groups[f]["chemical_system"].split("-"))
                for method in METHODS:
                    ranked = rows(folder / f"{method}.tsv")
                    original = rows(run / "baseline" / f"split-{s:02}/{method}.tsv")
                    formulas = [r["composition"] for r in ranked]
                    require(len(formulas)==n and set(formulas)==candidates, "incomplete/duplicate ranking")
                    fixed = [r for r in original if r["composition"] in candidates]
                    sort_keys = []
                    for i,r in enumerate(ranked,1):
                        f=r["composition"]
                        require(int(r["rank"])==i and r["tie_key"]==key("tie",20260901,f), "rank/tie mismatch")
                        require(r["observed_label"]==("positive" if f in heldout else "unlabelled"), "ranking label mismatch")
                        if mode=="evaluation_only":
                            old=fixed[i-1]
                            require(all(r[k]==old[k] for k in ("composition","score","random_key","tie_key")) and r["original_rank"]==old["rank"], "evaluation-only changed score/order/depth")
                        else:
                            require(r["original_rank"]=="", "full-pipeline cannot claim an original depth")
                        if policy=="original":
                            require(all(r[k]==original[i-1][k] for k in original[i-1]), "original control differs from v1")
                        if method=="random":
                            require(r["score"]=="" and r["random_key"]==key("random",s+10000,f), "random mismatch")
                            sort_keys.append((r["random_key"],r["tie_key"],f))
                        else:
                            score=float(r["score"])
                            require(math.isfinite(score) and 0<=score<=1 and r["random_key"]=="", "invalid score")
                            if method=="popularity":
                                elements=groups[f]["chemical_system"].split("-")
                                require(score==sum(frequencies[e] for e in elements)/(len(elements)*len(training)), "popularity mismatch")
                            sort_keys.append((-score,r["tie_key"],f))
                    require(sort_keys==sorted(sort_keys), "rank order mismatch")
                    if mode=="full_pipeline" and policy!="original":
                        shared=[(r["composition"],r["score"],r["random_key"],r["tie_key"]) for r in ranked if r["composition"] not in mixed]
                        if policy=="exclude_mixed":
                            common_rankings[s,method]=shared
                        else:
                            require(common_rankings[s,method]==shared, "shared-candidate score/order mismatch")
                    for k in budgets:
                        r=index[mode,policy,s,method,k]
                        hits=len(set(formulas[:k]) & heldout)
                        expectation=Fraction(k*h,n)
                        expected_ints=dict(training_count=len(training),mixed_training_count=len(training & mixed),mixed_candidate_count=len(candidates & mixed),policy_positive_count=len(eligible_p),policy_unlabelled_count=len(eligible_u),excluded_group_count=len(unresolved)+(len(mixed) if policy=="exclude_mixed" else 0),ranking_seed=s+10000,tie_seed=20260901,hits=hits,candidate_count=n,heldout_count=h,random_expected_hits_numerator=expectation.numerator,random_expected_hits_denominator=expectation.denominator)
                        for field,value in expected_ints.items():
                            require(int(r[field])==value, f"metric mismatch: {field}")
                        for field,value in dict(observed_label_fraction=hits/k,heldout_recall=hits/h,observed_label_enrichment=(hits/k)/(h/n),random_expected_hits=k*h/n).items():
                            require(float(r[field])==value, f"metric mismatch: {field}")
                        require(r["original_rank_depth"]==(ranked[k-1]["original_rank"] if mode=="evaluation_only" else ""), "original depth mismatch")
    return config,index,populations


def analyze(run, output):
    config,index,populations = validate(run)
    require(not output.exists(), "refusing to overwrite analysis")
    output.mkdir()
    seeds,budgets=config["split_seeds"],config["budgets"]
    paired,summary,method_summary=[],[],[]
    for mode in MODES:
        for policy in POLICIES:
            for k in budgets:
                diffs=[]
                changes=[]
                for s in seeds:
                    hits={m:int(index[mode,policy,s,m,k]["hits"]) for m in METHODS}
                    d=hits["similarity"]-hits["popularity"]
                    base=int(index[mode,"original",s,"similarity",k]["hits"])-int(index[mode,"original",s,"popularity",k]["hits"])
                    diffs.append(d); changes.append(d-base)
                    paired.append(dict(mode=mode,policy=policy,split_seed=s,budget=k,**hits,difference=d,change_from_original=d-base))
                summary.append(dict(mode=mode,policy=policy,budget=k,difference_mean=mean(diffs),difference_median=median(diffs),difference_min=min(diffs),difference_max=max(diffs),positive=sum(d>0 for d in diffs),zero=diffs.count(0),negative=sum(d<0 for d in diffs),change_from_original_mean=mean(changes)))
                for method in METHODS:
                    ms=[index[mode,policy,s,method,k] for s in seeds]
                    method_summary.append(dict(mode=mode,policy=policy,budget=k,method=method,**{field+"_mean":mean(float(r[field]) for r in ms) for field in ("hits","heldout_recall","observed_label_enrichment","random_expected_hits","candidate_count","heldout_count","training_count")},original_depth_min=min(int(r["original_rank_depth"]) for r in ms) if mode=="evaluation_only" else "",original_depth_max=max(int(r["original_rank_depth"]) for r in ms) if mode=="evaluation_only" else ""))
    write_rows(output/"paired-differences.tsv",paired)
    write_rows(output/"summary.tsv",summary)
    write_rows(output/"method-summary.tsv",method_summary)
    write_rows(output/"populations.tsv",populations)
    primary=[r for r in summary if r["budget"]==100]
    sign=lambda x:(x>0)-(x<0)
    full_primary=[r for r in primary if r["mode"]=="full_pipeline"]
    baseline=next((r for r in full_primary if r["policy"]=="original"),None)
    changed=[r["policy"] for r in full_primary if baseline and sign(r["difference_mean"])!=sign(baseline["difference_mean"])]
    decision=dict(full_pipeline_primary_sign_changes=changed,carry_both_alternatives_into_system_holdout=bool(changed),interpretation="A small sign change near zero is directional sensitivity, not proof of a robust reversal. Report magnitudes, populations and split variation.")
    (output/"decision.json").write_text(json.dumps(decision,indent=2)+"\n")
    (output/"validation.json").write_text(json.dumps(dict(status="passed",metrics=len(index),config_sha256=sha(run/"config.toml"),checks="file integrity; reconstructed policy memberships; fixed scores/order/depth; common-candidate invariance; original controls; random/popularity; complete metric grid and denominators",similarity="Full similarity recomputation is checked by the separate exact Julia rerun."),indent=2)+"\n")
    lines=["# Positive-label sensitivity results", "", "**Local only; unreviewed data derivatives.**", "", "Evaluation-only retains original training labels and saved scores. Exclusion filters and compacts eligible ranks; full-pipeline rebuilds training and candidates before scoring. These answer different questions.", "", "## Primary comparison at k=100", "", "D = similarity hits minus popularity hits. Changes from original compare policy-specific populations, not a controlled causal training-label effect.", "", "| Mode | Policy | Mean D | Median D | Range | + / 0 / − | Mean change from original |", "| --- | --- | ---: | ---: | --- | --- | ---: |"]
    if config["is_synthetic"]:
        lines.insert(4,"**Synthetic software fixture, not scientific evidence.**")
    for r in primary:
        lines.append(f"| {r['mode']} | {r['policy']} | {r['difference_mean']:+.2f} | {r['difference_median']:+.1f} | {r['difference_min']} to {r['difference_max']} | {r['positive']} / {r['zero']} / {r['negative']} | {r['change_from_original_mean']:+.2f} |")
    for mode in MODES:
        lines += ["",f"### Every primary split: {mode}","", "| Seed | Original D | Exclude mixed D | Unlabel mixed D |", "| --- | ---: | ---: | ---: |"]
        for s in seeds:
            values=[r["difference"] for p in POLICIES for r in paired if r["mode"]==mode and r["policy"]==p and r["split_seed"]==s and r["budget"]==100]
            if values:
                lines.append(f"| {s} | "+" | ".join(f"{v:+d}" for v in values)+" |")
    lines += ["", "## Population denominators", "", "Ranges across splits; every method within a branch uses the same population. Evaluation-only mixed training positives are retained deliberately.", "", "| Mode | Policy | Training | Candidates | Held-out positives | Mixed training |", "| --- | --- | --- | --- | --- | --- |"]
    for mode in MODES:
        for policy in POLICIES:
            ps=[r for r in populations if r["mode"]==mode and r["policy"]==policy]
            ranges=[f"{min(r[f] for r in ps)}–{max(r[f] for r in ps)}" for f in ("training_count","candidate_count","heldout_count","mixed_training_count")]
            lines.append(f"| {mode} | {policy} | "+" | ".join(ranges)+" |")
    lines += ["", "## All budgets and methods", "", "`summary.tsv` retains every paired effect at every budget. `method-summary.tsv` reports mean hits, recall, enrichment, uniform-random expectations and population counts. `paired-differences.tsv` retains every split, budget and change from original. `populations.tsv` records every branch population and prevalence. Original rank depths are explicit in the raw metrics; exclusion budgets count eligible candidates, so their original depths may exceed k.", "", "## Interpretation and next decision", "", f"Full-pipeline policies with a changed primary mean sign: {', '.join(changed) if changed else 'none'}.", "", "Carry both alternative policies into any later system-holdout design under the frozen decision rule." if changed else "The frozen sign-change rule does not trigger mandatory carry-forward; all magnitude changes and evaluation-only diagnostics remain part of the evidence.", "", "Variation is descriptive split sensitivity across overlapping holdouts, with no confidence intervals or significance claims. A small reversal near zero does not establish a robust advantage. Changing pool sizes, prevalence and training sizes can affect raw hits and enrichment; these branches do not isolate a causal mechanism. Neither treatment of mixed flags has been independently validated as ground truth.", "", "The positive label is an MP experimental-provenance proxy, not verified synthesis success. Unlabelled candidates are not failed syntheses. MP coverage, mixed polymorphs, normalization and historical research effort constrain interpretation. Random composition holdout permits shared systems and close analogues; system holdout has not been run. Learned methods and literature-based relabelling remain deferred.", "", "See the parent directory's design/implementation freeze records and exact-rerun comparison. Original v1 artifacts remain untouched. Validation here reconstructs policy memberships, ranking invariants and metrics independently; exact Julia reproduction supplies the full similarity-score recomputation check.", ""]
    (output/"report.md").write_text("\n".join(lines))
    return primary


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run",type=Path)
    parser.add_argument("output",type=Path)
    args=parser.parse_args()
    print(json.dumps(analyze(args.run,args.output),indent=2))
