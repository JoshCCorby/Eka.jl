#!/usr/bin/env python3
"""Independent membership, population, ranking and diagnostic checks for v2."""
import argparse
import hashlib
import json
import math
import re
import tomllib
from collections import Counter
from fractions import Fraction
from pathlib import Path
from statistics import mean, median

from analyze_pu_pilot import key, require, rows, sha, write_rows

PROTOCOL_SHA = "2a9d056c65fe8fe31878f445857d539666b39f8310b1bf93453fc65da41cf263"
DESIGNS = ("composition", "system")
POLICIES = ("original", "exclude_mixed", "unlabel_mixed")
METHODS = ("random", "popularity", "similarity")


def vector(formula):
    terms = re.findall(r"([A-Z][a-z]?)([0-9]+)", formula)
    require("".join(e+n for e,n in terms) == formula, "invalid canonical formula")
    return {e:int(n) for e,n in terms}


def system(formula):
    return "-".join(sorted(vector(formula)))


def system_key(seed, name):
    return hashlib.sha256(f"eka-pu-system-split-v2\n{seed}\n{name}".encode()).hexdigest()


def selected_systems(universe, seed):
    return set(sorted(universe, key=lambda x:(system_key(seed,x),x))[:len(universe)//5])


def concentration(formulas):
    counts = sorted(Counter(system(f) for f in formulas).values(), reverse=True)
    return counts[0]/len(formulas), sum(counts[:5])/len(formulas)


def describe(values):
    n = len(values)
    ordered = sorted(values)
    q = lambda p: ordered[max(1,math.ceil(p*n))-1]
    total = 0.0
    for value in values:
        total += value
    return dict(n=n,mean=total/n,min=min(values),p10=q(.1),median=q(.5),p90=q(.9),max=max(values),
                fraction_ge_09=sum(x>=.9 for x in values)/n,fraction_ge_099=sum(x>=.99 for x in values)/n)


def safe(name):
    require(not Path(name).is_absolute() and ".." not in Path(name).parts and "\\" not in name, "unsafe inventory path")


def validate(run):
    cfg = tomllib.loads((run/"config.toml").read_text())
    require(cfg["protocol_id"]=="eka-mp-system-holdout-v2" and cfg["protocol_sha256"]==PROTOCOL_SHA and sha(run/"protocol.md")==PROTOCOL_SHA,"wrong protocol")
    require(cfg["designs"]==list(DESIGNS) and cfg["policies"]==list(POLICIES) and cfg["methods"]==list(METHODS),"wrong experiment grid")
    seeds,budgets=cfg["split_seeds"],cfg["budgets"]
    require(seeds==sorted(set(seeds)) and budgets==sorted(set(budgets)) and seeds and budgets,"invalid seeds/budgets")
    require(cfg["ranking_seeds"]==[s+10000 for s in seeds] and cfg["tie_seed"]==20260901,"wrong ranking seeds")
    require(cfg["is_synthetic"] or (seeds==list(range(20)) and budgets==[20,50,100,200]),"incomplete real experiment")
    actual={p.relative_to(run).as_posix() for p in run.rglob("*") if p.is_file()}-{"config.toml","runtime.tsv"}
    require(actual==set(cfg["deterministic_file_hashes"]),"wrong file inventory")
    for name,digest in cfg["deterministic_file_hashes"].items():
        safe(name);require(sha(run/name)==digest,f"hash mismatch: {name}")
    for prefix,field in (("source","input_hashes"),("implementation","implementation_hashes")):
        for name,digest in cfg[field].items():
            safe(name);require(sha(run/prefix/name)==digest,f"{prefix} identity mismatch")
    require(sha(run/"baseline/config.toml")==cfg["baseline_config_sha256"],"baseline identity mismatch")
    bc=tomllib.loads((run/"baseline/config.toml").read_text())
    require(bc["protocol_id"]=="eka-mp-label-sensitivity-v1" and bc["input_hashes"]==cfg["input_hashes"],"baseline source/protocol mismatch")
    for path in (run/"baseline").rglob("*"):
        if path.is_file() and path.name!="config.toml":
            require(sha(path)==bc["deterministic_file_hashes"][path.relative_to(run/"baseline").as_posix()],"baseline content mismatch")
    source=rows(run/"source/audit/compositions.tsv")
    groups={r["composition"]:r for r in source}
    require(len(groups)==len(source),"duplicate source groups")
    systems={f:system(f) for f in groups}
    require(all(systems[f]==r["chemical_system"] for f,r in groups.items()),"incorrect source system")
    p={f for f,r in groups.items() if r["label"]=="positive"}
    u={f for f,r in groups.items() if r["label"]=="unlabelled"}
    unresolved=set(groups)-p-u
    mixed={f for f,r in groups.items() if int(r["experimental_records"])>0 and int(r["theoretical_records"])>0}
    require(mixed<=p,"invalid mixed labels")
    universe={systems[f] for f in p|u}
    raw=rows(run/"metrics.tsv")
    index={(r["design"],r["policy"],int(r["split_seed"]),r["method"],int(r["budget"])):r for r in raw}
    expected={(d,p,s,m,k) for d in DESIGNS for p in POLICIES for s in seeds for m in METHODS for k in budgets}
    require(len(raw)==len(index) and set(index)==expected,"incomplete/duplicate metric grid")
    population_rows=rows(run/"populations.tsv")
    populations={(r["design"],r["policy"],int(r["split_seed"])):r for r in population_rows}
    branch_keys={(d,p,s) for d in DESIGNS for p in POLICIES for s in seeds}
    require(len(population_rows)==len(populations) and set(populations)==branch_keys,"incomplete population grid")
    diagnostic_rows=rows(run/"similarity-diagnostics.tsv")
    diagnostics={(r["design"],r["policy"],int(r["split_seed"]),r["subset"]):r for r in diagnostic_rows}
    require(len(diagnostic_rows)==len(diagnostics) and set(diagnostics)=={(*b,k) for b in branch_keys for k in ("all","positive","unlabelled")},"incomplete diagnostic grid")
    bm={(r["policy"],int(r["split_seed"]),r["method"],int(r["budget"])):r for r in rows(run/"baseline/metrics.tsv") if r["mode"]=="full_pipeline"}
    shared={}
    for design in DESIGNS:
        for policy in POLICIES:
            ep=p if policy=="original" else p-mixed
            eu=u|mixed if policy=="unlabel_mixed" else u
            for seed in seeds:
                chosen=selected_systems(universe,seed) if design=="system" else set()
                h={f for f in ep if systems[f] in chosen} if design=="system" else set(sorted(ep,key=lambda f:(key("split",seed,f),f))[:len(ep)//5])
                t=ep-h
                c=h|({f for f in eu if systems[f] in chosen} if design=="system" else eu)
                n,nh=len(c),len(h)
                require(t and h and n>nh and n>=max(budgets),"infeasible population")
                st,sc,sh=({systems[f] for f in v} for v in (t,c,h))
                require(not t&c and (design!="system" or not st&sc),"membership/system overlap")
                prefix=run/design/policy/f"split-{seed:02}"
                for name,values in (("inputs/training.tsv",t),("inputs/candidates.tsv",c),("evaluation/heldout.tsv",h)):
                    require([r["composition"] for r in rows(prefix/name)]==sorted(values),"membership mismatch")
                    if design=="composition":
                        require((prefix/name).read_bytes()==(run/"baseline/full_pipeline"/policy/f"split-{seed:02}"/name).read_bytes(),"control membership mismatch")
                labels=rows(prefix/"evaluation/labels.tsv")
                require([r["composition"] for r in labels]==sorted(c) and all(r["label"]==("positive" if r["composition"] in h else "unlabelled") for r in labels),"label mismatch")
                if design=="system":
                    require([r["chemical_system"] for r in rows(prefix/"selected-systems.tsv")]==sorted(chosen),"selected-system mismatch")
                pop=populations[design,policy,seed]
                ints=dict(training_count=len(t),candidate_count=n,heldout_count=nh,unlabelled_count=n-nh,
                    excluded_group_count=len(unresolved)+(len(mixed) if policy=="exclude_mixed" else 0),unused_unlabelled_count=len(eu)-(n-nh),
                    universe_system_count=len(universe),selected_system_count=len(chosen),selected_empty_system_count=len(chosen-sc),
                    training_system_count=len(st),candidate_system_count=len(sc),heldout_system_count=len(sh),system_overlap_count=len(st&sc),
                    mixed_training_count=len(t&mixed),mixed_candidate_count=len(c&mixed))
                for field,value in ints.items():
                    require(int(pop[field])==value,f"population mismatch: {field}")
                for field,value in zip(("training_largest_system_fraction","training_top5_system_fraction","heldout_largest_system_fraction","heldout_top5_system_fraction"),(*concentration(t),*concentration(h))):
                    require(float(pop[field])==value,"positive concentration mismatch")
                require(float(pop["prevalence"])==nh/n,"prevalence mismatch")
                frequency=Counter(e for f in t for e in vector(f))
                for method in METHODS:
                    ranked=rows(prefix/f"{method}.tsv")
                    formulas=[r["composition"] for r in ranked]
                    require(len(formulas)==n and set(formulas)==c,"incomplete ranking")
                    order=[]
                    for i,r in enumerate(ranked,1):
                        f=r["composition"]
                        require(int(r["rank"])==i and r["tie_key"]==key("tie",20260901,f),"rank/tie mismatch")
                        require(r["observed_label"]==("positive" if f in h else "unlabelled"),"ranking label mismatch")
                        if method=="random":
                            require(r["score"]=="" and r["random_key"]==key("random",seed+10000,f),"random key mismatch")
                            order.append((r["random_key"],r["tie_key"],f))
                        else:
                            score=float(r["score"])
                            require(math.isfinite(score) and 0<=score<=1 and r["random_key"]=="","invalid score")
                            if method=="popularity":
                                require(score==sum(frequency[e] for e in vector(f))/(3*len(t)),"popularity mismatch")
                            order.append((-score,r["tie_key"],f))
                    require(order==sorted(order),"ranking order mismatch")
                    if design=="composition":
                        old=rows(run/"baseline/full_pipeline"/policy/f"split-{seed:02}"/f"{method}.tsv")
                        require(len(old)==len(ranked) and all(all(r[k]==prior[k] for k in r) for r,prior in zip(ranked,old)),"control ranking mismatch")
                    common=[{k:r[k] for k in ("composition","score","random_key","tie_key")} for r in ranked if r["composition"] not in mixed]
                    if policy=="exclude_mixed": shared[design,seed,method]=common
                    if policy=="unlabel_mixed": require(shared[design,seed,method]==common,"shared scores/order mismatch")
                    for budget in budgets:
                        metric=index[design,policy,seed,method,budget]
                        hits=len(set(formulas[:budget])&h)
                        frac=Fraction(budget*nh,n)
                        for field,value in dict(training_count=len(t),candidate_count=n,heldout_count=nh,hits=hits,random_expected_hits_numerator=frac.numerator,random_expected_hits_denominator=frac.denominator).items():
                            require(int(metric[field])==value,f"metric mismatch: {field}")
                        for field,value in dict(observed_label_fraction=hits/budget,heldout_recall=hits/nh,observed_label_enrichment=(hits/budget)/(nh/n),random_expected_hits=budget*nh/n).items():
                            require(float(metric[field])==value,f"metric mismatch: {field}")
                        if design=="composition":
                            prior=bm[policy,seed,method,budget]
                            require(all(metric[k]==prior[k] for k in metric if k!="design"),"control metric mismatch")
                    if method=="similarity":
                        scores={r["composition"]:float(r["score"]) for r in ranked}
                        detail=rows(prefix/"candidate-similarity.tsv")
                        require([r["composition"] for r in detail]==sorted(c),"diagnostic membership mismatch")
                        require(all(float(r["maximum_similarity"])==scores[r["composition"]] and r["observed_label"]==("positive" if r["composition"] in h else "unlabelled") for r in detail),"diagnostic score/label mismatch")
                        for subset in ("all","positive","unlabelled"):
                            values=[scores[f] for f in sorted(c) if subset=="all" or ("positive" if f in h else "unlabelled")==subset]
                            record=diagnostics[design,policy,seed,subset]
                            for field,value in describe(values).items():
                                require(float(record[field])==value,f"diagnostic mismatch: {field}")
    return cfg,index,population_rows,diagnostic_rows


def analyze(run,output):
    cfg,index,populations,diagnostics=validate(run)
    require(not output.exists(),"refusing to overwrite analysis")
    output.mkdir()
    seeds,budgets=cfg["split_seeds"],cfg["budgets"]
    paired,summary,methods=[],[],[]
    for design in DESIGNS:
        for policy in POLICIES:
            for k in budgets:
                diffs=[];changes=[]
                for s in seeds:
                    hits={m:int(index[design,policy,s,m,k]["hits"]) for m in METHODS}
                    d=hits["similarity"]-hits["popularity"]
                    base=int(index["composition",policy,s,"similarity",k]["hits"])-int(index["composition",policy,s,"popularity",k]["hits"])
                    diffs.append(d);changes.append(d-base)
                    paired.append(dict(design=design,policy=policy,split_seed=s,budget=k,**hits,difference=d,change_from_composition=d-base))
                summary.append(dict(design=design,policy=policy,budget=k,difference_mean=mean(diffs),difference_median=median(diffs),difference_min=min(diffs),difference_max=max(diffs),positive=sum(d>0 for d in diffs),zero=diffs.count(0),negative=sum(d<0 for d in diffs),change_from_composition_mean=mean(changes)))
                for m in METHODS:
                    ms=[index[design,policy,s,m,k] for s in seeds]
                    methods.append(dict(design=design,policy=policy,budget=k,method=m,**{f+"_mean":mean(float(r[f]) for r in ms) for f in ("hits","heldout_recall","observed_label_enrichment","random_expected_hits","training_count","candidate_count","heldout_count")}))
    for name,data in (("paired-differences.tsv",paired),("summary.tsv",summary),("method-summary.tsv",methods),("populations.tsv",populations),("similarity-diagnostics.tsv",diagnostics)):
        write_rows(output/name,data)
    primary=[r for r in summary if r["budget"]==100]
    lines=["# Chemical-system holdout results","","Synthetic checks only." if cfg["is_synthetic"] else "Same frozen MP snapshot; all three full-pipeline label policies.","","## Primary comparison at k=100","","D = similarity hits minus popularity hits. Changes compare protocols with different populations, not a causal separation effect.","","| Design | Policy | Mean D | Median D | Range | + / 0 / − | Change from composition mean |","| --- | --- | ---: | ---: | --- | --- | ---: |"]
    for r in primary:
        lines.append(f"| {r['design']} | {r['policy']} | {r['difference_mean']:+.2f} | {r['difference_median']:+.1f} | {r['difference_min']} to {r['difference_max']} | {r['positive']} / {r['zero']} / {r['negative']} | {r['change_from_composition_mean']:+.2f} |")
    lines += ["","## Population ranges","","| Design | Policy | Training | Candidates | Held-out positives | Prevalence |","| --- | --- | --- | --- | --- | --- |"]
    for design in DESIGNS:
        for policy in POLICIES:
            ps=[r for r in populations if r["design"]==design and r["policy"]==policy]
            ranges=[f"{min(float(r[f]) for r in ps):.4g}–{max(float(r[f]) for r in ps):.4g}" for f in ("training_count","candidate_count","heldout_count","prevalence")]
            lines.append(f"| {design} | {policy} | "+" | ".join(ranges)+" |")
    lines += ["","## Candidate-to-training similarity","","Mean across splits of each split's candidate mean maximum cosine. Full distributions, label subsets, p10/median/p90 and >=0.9/0.99 fractions are in similarity-diagnostics.tsv.","","| Design | Policy | All candidates | Held-out positives | Unlabelled |","| --- | --- | ---: | ---: | ---: |"]
    for design in DESIGNS:
        for policy in POLICIES:
            vals=[mean(float(r["mean"]) for r in diagnostics if r["design"]==design and r["policy"]==policy and r["subset"]==subset) for subset in ("all","positive","unlabelled")]
            lines.append(f"| {design} | {policy} | "+" | ".join(f"{v:.6f}" for v in vals)+" |")
    lines += ["","## Every primary split","","| Seed | Policy | Composition D | System D | Difference |","| --- | --- | ---: | ---: | ---: |"]
    if 100 in budgets:
        for policy in POLICIES:
            for s in seeds:
                x=next(r for r in paired if r["design"]=="composition" and r["policy"]==policy and r["split_seed"]==s and r["budget"]==100)
                y=next(r for r in paired if r["design"]=="system" and r["policy"]==policy and r["split_seed"]==s and r["budget"]==100)
                lines.append(f"| {s} | {policy} | {x['difference']:+d} | {y['difference']:+d} | {y['change_from_composition']:+d} |")
    lines += ["","## Interpretation limits","","All budgets, random expectations and method means are retained in the TSVs. Population files include unused unlabelled groups, selected empty systems, mixed counts, observed system overlap and concentration of training/held-out positives in the largest and top five systems.","","This tests unseen element combinations, not necessarily chemically distant materials. Training sizes, candidate competition and prevalence differ; there is no matched-size control and no causal separation claim. Elemental cosine is a descriptive representation, not a learned chemistry distance. Split variation is descriptive across overlapping samples, with no significance tests or confidence intervals. The positive label is experimental provenance, not verified synthesis success; unlabelled does not mean failed.","","Controls reconstruct saved full-pipeline sensitivity results exactly. This analyzer independently reconstructs memberships, random/popularity scores, ranking order, metrics, populations and similarity summaries. Full similarity scores must also be recomputed by the separate Julia rerun. Prior frozen evidence remains unchanged. No learned model has been run. Data remain local pending final attributed release review.",""]
    (output/"report.md").write_text("\n".join(lines))
    (output/"validation.json").write_text(json.dumps(dict(status="passed",metrics=len(index),branches=len(populations),diagnostic_rows=len(diagnostics),config_sha256=sha(run/"config.toml"),similarity="Summaries checked independently; full score recomputation requires the separate Julia rerun."),indent=2)+"\n")
    return primary


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run",type=Path);parser.add_argument("output",type=Path)
    args=parser.parse_args()
    print(json.dumps(analyze(args.run,args.output),indent=2))
