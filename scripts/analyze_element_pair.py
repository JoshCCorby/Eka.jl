#!/usr/bin/env python3
"""Independent checks and complete reporting for the frozen pair-factor evaluation."""
import argparse
import hashlib
import json
import math
import tomllib
from collections import Counter
from fractions import Fraction
from pathlib import Path
from statistics import mean,median
from analyze_pu_pilot import require,rows,sha,write_rows,key
from analyze_system_holdout import vector,system,selected_systems,DESIGNS,POLICIES,safe

PROTOCOL_SHA="4482edc21c5efb4a65d4923ec985dcef526efd55106fbb521fe214487b563c01"
BASELINE_SHA="c55cc2cf29f75b74abda3dc66194043339b564cf1614d925434adcb581932565"
SETTINGS=dict(rank=4,missing_weight=0.01,regularization=0.01,seed=20260902,max_iterations=2000,tolerance=1e-4)
ELEMENTS=sorted(set('H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og'.split())-{'O'})


def pair(f):return tuple(e for e in sorted(vector(f)) if e!='O')


def numerical_state(factors,counts,t):
    # Independent objective/gradient calculation from the actual saved factors.
    gradient={e:[0.01*x for x in factors[e]] for e in ELEMENTS}
    loss=0.005*sum(x*x for row in factors.values() for x in row)
    for i,a in enumerate(ELEMENTS):
        for b in ELEMENTS[i+1:]:
            count=counts.get((a,b),0)
            residual=sum(x*y for x,y in zip(factors[a],factors[b]))-math.log1p(count)/math.log1p(t)
            weighted=(1.0 if count else 0.01)*residual
            loss+=0.5*weighted*residual
            for k in range(4):
                gradient[a][k]+=weighted*factors[b][k]
                gradient[b][k]+=weighted*factors[a][k]
    pg=math.sqrt(sum((x-max(0,x-g))**2 for e in ELEMENTS for x,g in zip(factors[e],gradient[e])))
    return loss,pg


def validate(run):
    cfg=tomllib.loads((run/'config.toml').read_text())
    require(cfg['protocol_id']=='eka-mp-element-pair-v1' and cfg['protocol_sha256']==PROTOCOL_SHA and sha(run/'protocol.md')==PROTOCOL_SHA,'protocol mismatch')
    require(cfg['settings']==SETTINGS and cfg['model_id']=='eka-element-pair-symnmf-v1' and cfg['tie_seed']==20260901,'model configuration mismatch')
    require(cfg['designs']==list(DESIGNS) and cfg['policies']==list(POLICIES),'wrong branches')
    seeds,budgets=cfg['split_seeds'],cfg['budgets']
    require(cfg['is_synthetic'] or (seeds==list(range(20)) and budgets==[20,50,100,200]),'wrong real grid')
    actual={p.relative_to(run).as_posix() for p in run.rglob('*') if p.is_file()}-{'config.toml','runtime.tsv'}
    require(actual==set(cfg['deterministic_file_hashes']),'wrong file inventory')
    for name,digest in cfg['deterministic_file_hashes'].items():safe(name);require(sha(run/name)==digest,f'hash mismatch: {name}')
    for prefix,field in (('source','input_hashes'),('implementation','implementation_hashes')):
        for name,digest in cfg[field].items():safe(name);require(sha(run/prefix/name)==digest,f'{prefix} identity mismatch')
    bh=sha(run/'baseline/config.toml')
    require(bh==cfg['baseline_config_sha256'] and (cfg['is_synthetic'] or bh==BASELINE_SHA),'baseline config pin mismatch')
    bc=tomllib.loads((run/'baseline/config.toml').read_text())
    require(bc['input_hashes']==cfg['input_hashes'],'baseline source mismatch')
    for p in (run/'baseline').rglob('*'):
        if p.is_file() and p.name!='config.toml':require(sha(p)==bc['deterministic_file_hashes'][p.relative_to(run/'baseline').as_posix()],'captured baseline hash mismatch')
    gs=rows(run/'source/audit/compositions.tsv');groups={r['composition']:r for r in gs}
    require(len(groups)==len(gs),'duplicate source groups')
    positives={f for f,r in groups.items() if r['label']=='positive'};unlabelled={f for f,r in groups.items() if r['label']=='unlabelled'}
    mixed={f for f,r in groups.items() if int(r['experimental_records'])>0 and int(r['theoretical_records'])>0}
    universe={system(f) for f in positives|unlabelled}
    raw=rows(run/'metrics.tsv');idx={(r['design'],r['policy'],int(r['split_seed']),int(r['budget'])):r for r in raw}
    require(len(raw)==len(idx) and set(idx)=={(d,p,s,k) for d in DESIGNS for p in POLICIES for s in seeds for k in budgets},'incomplete metric grid')
    diagnostic=rows(run/'fit-diagnostics.tsv');di={(r['design'],r['policy'],int(r['split_seed'])):r for r in diagnostic}
    require(len(di)==len(diagnostic) and set(di)=={(d,p,s) for d in DESIGNS for p in POLICIES for s in seeds},'incomplete fit grid')
    baseline=rows(run/'baseline/metrics.tsv');bi={(r['design'],r['policy'],int(r['split_seed']),r['method'],int(r['budget'])):r for r in baseline}
    require(len(baseline)==len(bi) and set(bi)=={(d,p,s,m,k) for d in DESIGNS for p in POLICIES for s in seeds for m in ('random','popularity','similarity') for k in budgets},'incomplete baseline grid')
    shared={}
    for d in DESIGNS:
        for p in POLICIES:
            ep=positives if p=='original' else positives-mixed
            eu=unlabelled|mixed if p=='unlabel_mixed' else unlabelled
            for s in seeds:
                chosen=selected_systems(universe,s)
                h={f for f in ep if system(f) in chosen} if d=='system' else set(sorted(ep,key=lambda f:(key('split',s,f),f))[:len(ep)//5])
                t=ep-h;c=h|({f for f in eu if system(f) in chosen} if d=='system' else eu)
                sub=Path(d)/p/f'split-{s:02}';folder=run/sub;prior=run/'baseline'/sub
                for name,members in (('inputs/training.tsv',t),('inputs/candidates.tsv',c),('evaluation/heldout.tsv',h)):
                    require([r['composition'] for r in rows(prior/name)]==sorted(members),'reconstructed membership mismatch')
                labels=rows(prior/'evaluation/labels.tsv')
                require([r['composition'] for r in labels]==sorted(c) and all(r['label']==('positive' if r['composition'] in h else 'unlabelled') for r in labels),'baseline evaluation-label mismatch')
                counts=Counter(pair(f) for f in t);active={e for f in t for e in pair(f)}
                cr=rows(folder/'pair-counts.tsv');require(len(cr)==len(counts) and {(r['element_a'],r['element_b']):int(r['count']) for r in cr}==counts,'pair-count mismatch')
                fr=rows(folder/'factors.tsv');require(len(fr)==117*4,'incomplete factor matrix')
                require([(r['element'],int(r['factor'])) for r in fr]==[(e,k) for e in ELEMENTS for k in range(1,5)],'factor axes mismatch')
                factors={e:[float(r['value']) for r in fr if r['element']==e] for e in ELEMENTS}
                require(all(math.isfinite(x) and x>=0 for v in factors.values() for x in v),'invalid factor value')
                require(all(r['seen_in_training']==str(r['element'] in active).lower() for r in fr),'active-element mismatch')
                require(all(all(x==0 for x in factors[e]) for e in set(ELEMENTS)-active),'nonzero cold factors')
                trace=rows(folder/'objective.tsv');dg=di[d,p,s]
                require([int(r['iteration']) for r in trace]==list(range(len(trace))) and len(trace)<=2001,'iteration trace mismatch')
                losses=[float(r['objective']) for r in trace];residuals=[float(r['projected_gradient']) for r in trace]
                require(all(math.isfinite(x) and x>=0 for x in losses+residuals) and all(b<=a for a,b in zip(losses,losses[1:])),'nonmonotonic/invalid objective')
                loss,pg=numerical_state(factors,counts,len(t))
                require(math.isclose(loss,losses[-1],rel_tol=1e-10,abs_tol=1e-12) and math.isclose(pg,residuals[-1],rel_tol=1e-9,abs_tol=1e-12),'factor objective/gradient mismatch')
                threshold=1e-4*max(1,residuals[0]);stop='projected_gradient' if residuals[-1]<=threshold else 'iteration_limit'
                require(dg['termination']==stop and (stop!='iteration_limit' or len(trace)==2001),'termination mismatch')
                ranked=rows(folder/'ranking.tsv');fs=[r['composition'] for r in ranked]
                require(len(fs)==len(c) and set(fs)==c,'incomplete ranking')
                order=[]
                for i,r in enumerate(ranked,1):
                    f=r['composition'];a,b=pair(f);known=a in active and b in active
                    score=0.0
                    if known:
                        # Match the specified sequential Float64 score arithmetic;
                        # Python 3.12+ sum uses a different summation algorithm.
                        for x,y in zip(factors[a],factors[b]):score+=x*y
                    require(float(r['score'])==score,'factor score mismatch')
                    require(r['coverage']==('known_elements' if known else 'unseen_element_zero') and r['observed_training_pair']==str((a,b) in counts).lower(),'coverage mismatch')
                    require(int(r['rank'])==i and r['tie_key']==key('tie',20260901,f),'rank/tie mismatch')
                    require(r['observed_label']==('positive' if f in h else 'unlabelled'),'ranking label mismatch')
                    order.append((-score,r['tie_key'],f))
                require(order==sorted(order),'ranking order mismatch')
                freq=Counter(float(r['score']) for r in ranked)
                expected=dict(training_count=len(t),candidate_count=len(c),heldout_count=len(h),active_elements=len(active),cold_candidates=sum(r['coverage']=='unseen_element_zero' for r in ranked),distinct_scores=len(freq),tied_candidates=sum(n for n in freq.values() if n>1),iterations=len(trace)-1)
                for field,value in expected.items():require(int(dg[field])==value,f'fit diagnostic mismatch: {field}')
                require(dg['training_sha256']==sha(prior/'inputs/training.tsv') and float(dg['prevalence'])==len(h)/len(c),'training identity/prevalence mismatch')
                require(float(dg['initial_objective'])==losses[0] and float(dg['final_objective'])==losses[-1] and float(dg['final_projected_gradient'])==residuals[-1],'fit trace summary mismatch')
                common=[{k:r[k] for k in ('composition','score','coverage','observed_training_pair','tie_key')} for r in ranked if r['composition'] not in mixed]
                state=((folder/'factors.tsv').read_bytes(),(folder/'objective.tsv').read_bytes(),common)
                if p=='exclude_mixed':shared[d,s]=state
                if p=='unlabel_mixed':require(shared[d,s]==state,'alternative-policy fit/shared scores differ')
                for k in budgets:
                    r=idx[d,p,s,k];hits=len(set(fs[:k])&h);fraction=Fraction(k*len(h),len(c))
                    require(r['method']=='element_pair','wrong method')
                    for field,value in dict(hits=hits,candidate_count=len(c),heldout_count=len(h),random_expected_hits_numerator=fraction.numerator,random_expected_hits_denominator=fraction.denominator).items():require(int(r[field])==value,f'metric mismatch: {field}')
                    for field,value in dict(observed_label_fraction=hits/k,heldout_recall=hits/len(h),observed_label_enrichment=(hits/k)/(len(h)/len(c)),random_expected_hits=float(fraction)).items():require(float(r[field])==value,f'metric mismatch: {field}')
    return cfg,idx,bi,diagnostic


def analyze(run,output):
    cfg,idx,baseline,diagnostics=validate(run);require(not output.exists(),'refusing to overwrite analysis');output.mkdir()
    paired=[];summary=[];method_summary=[]
    for d in DESIGNS:
        for p in POLICIES:
            for k in cfg['budgets']:
                ds=[];secondary=[]
                for s in cfg['split_seeds']:
                    hits={m:int(baseline[d,p,s,m,k]['hits']) for m in ('random','popularity','similarity')};hits['element_pair']=int(idx[d,p,s,k]['hits'])
                    a=hits['element_pair']-hits['popularity'];b=hits['element_pair']-hits['similarity'];ds.append(a);secondary.append(b)
                    paired.append(dict(design=d,policy=p,split_seed=s,budget=k,**hits,minus_popularity=a,minus_similarity=b))
                summary.append(dict(design=d,policy=p,budget=k,mean_difference=mean(ds),median_difference=median(ds),min_difference=min(ds),max_difference=max(ds),positive=sum(x>0 for x in ds),zero=ds.count(0),negative=sum(x<0 for x in ds),mean_minus_similarity=mean(secondary)))
                for m in ('random','popularity','similarity','element_pair'):
                    rs=[idx[d,p,s,k] if m=='element_pair' else baseline[d,p,s,m,k] for s in cfg['split_seeds']]
                    method_summary.append(dict(design=d,policy=p,budget=k,method=m,**{f+'_mean':mean(float(r[f]) for r in rs) for f in ('hits','heldout_recall','observed_label_enrichment','random_expected_hits','candidate_count','heldout_count')}))
    for name,data in (('paired-differences.tsv',paired),('summary.tsv',summary),('method-summary.tsv',method_summary),('fit-diagnostics.tsv',diagnostics)):write_rows(output/name,data)
    primary=[r for r in summary if r['budget']==100]
    lines=['# Element-pair model evaluation','','Synthetic software checks only.' if cfg['is_synthetic'] else 'Fixed-compute model; all methods use identical candidates within each branch/split.','','| Design | Policy | Model − popularity mean Hits@100 | Median | Range | + / 0 / − | Model − similarity mean |','| --- | --- | ---: | ---: | --- | --- | ---: |']
    for r in primary:lines.append(f"| {r['design']} | {r['policy']} | {r['mean_difference']:+.2f} | {r['median_difference']:+.1f} | {r['min_difference']} to {r['max_difference']} | {r['positive']}/{r['zero']}/{r['negative']} | {r['mean_minus_similarity']:+.2f} |")
    lines+=['','## Optimization and coverage','','| Design | Policy | Converged | Capped | Iteration range | Cold candidates range | Tied candidates range |','| --- | --- | ---: | ---: | --- | --- | --- |']
    for d in DESIGNS:
        for p in POLICIES:
            ds=[r for r in diagnostics if r['design']==d and r['policy']==p]
            ranges=[f"{min(int(r[f]) for r in ds)}–{max(int(r[f]) for r in ds)}" for f in ('iterations','cold_candidates','tied_candidates')]
            lines.append(f"| {d} | {p} | {sum(r['termination']=='projected_gradient' for r in ds)} | {sum(r['termination']=='iteration_limit' for r in ds)} | "+' | '.join(ranges)+' |')
    lines+=['','## Every primary split','','| Design | Policy | Seed | Model − popularity | Model − similarity |','| --- | --- | ---: | ---: | ---: |']
    for r in paired:
        if r['budget']==100:lines.append(f"| {r['design']} | {r['policy']} | {r['split_seed']} | {r['minus_popularity']:+d} | {r['minus_similarity']:+d} |")
    lines+=['','All methods and budgets, random expectations, recall/enrichment and population denominators appear in method-summary.tsv. Fit diagnostics retain training hashes, population counts/prevalence, coverage, ties and final objective/stationarity. Full objective traces and factors are in the raw run.','', 'This model ignores stoichiometry and applies a low-confidence zero-target assumption to missing pair associations. Unlabelled compounds are not verified negatives. A capped fit is a fixed-compute state, not a converged optimum. No hyperparameter search, significance tests or confidence intervals were used. Different holdout populations prevent a causal separation claim. These results do not establish synthesis success, chemical-distance generalization or a reproduction of Seko.','', 'Independent checks reconstruct memberships, pair counts and active elements; recompute every score and final objective/projected gradient from factors; verify ranking, metrics, termination, coverage and shared-policy invariance. Full refitting reproduction is recorded separately.','']
    (output/'report.md').write_text('\n'.join(lines))
    (output/'validation.json').write_text(json.dumps(dict(status='passed',metrics=len(idx),fits=len(diagnostics),config_sha256=sha(run/'config.toml')),indent=2)+'\n')
    return primary

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
    print(json.dumps(analyze(args.run,args.output),indent=2))
