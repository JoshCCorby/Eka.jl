# Learned comparator: specification and feasibility gate

Prepared 31 August 2026 after system holdout v2. This is a development and
feasibility specification, not a frozen scientific evaluation protocol. No real
outer-test rankings or labels may be used to select this model's configuration.
The completed pilot, sensitivity and system-holdout results remain unchanged.

## Question and representation

Can a low-rank model of training element co-occurrence add useful association
information beyond element popularity and nearest-composition cosine when
ranking unseen oxygen-containing ternary systems?

Prototype ID: `eka-element-pair-symnmf-v1`. Use a symmetric nonnegative factor
model of the two **non-oxygen** elements. Oxygen is constant in the experiment's
scope; removing it from these axes prevents a universal O node from defining the
association matrix. Axes are the 117 non-O elements in Eka's fixed periodic-table
vocabulary, sorted alphabetically, independent of candidates and test labels.

For each unique canonical training-positive composition, increment the count of
its unordered non-O pair once. Multiple stoichiometries of a pair contribute
multiple observations; repeated canonical formulas are rejected. Let T be the
number of training compositions and C_ab this count. For distinct elements:

`Y_ab = log(1 + C_ab) / log(1 + T)`.

Fit nonnegative F with 117 rows and rank r. Prediction for pair (a,b) is the dot
product of their factor rows. The objective, over unordered pairs a<b, is:

`0.5 * sum_ab w_ab * (dot(F_a,F_b) - Y_ab)^2 + 0.5 * lambda * sum_ak F_ak^2`.

Observed pairs have weight 1; missing pairs have weight alpha. Diagonals are
excluded. Initial fixed feasibility settings: rank 4, alpha=0.01, lambda=0.01,
initialization seed 20260902, at most 2,000 projected-gradient iterations,
relative projected-gradient tolerance 1e-4. These are engineering defaults,
not settings chosen from real recovery performance.

Nonnegative projected gradient descent uses Armijo backtracking (coefficient
1e-4, halving step, at most 60 trials). Initial step is 1; subsequent trial steps
are min(1, twice the last accepted step). The stationarity residual is the
Frobenius norm of `F - max(0, F - gradient)`, with stopping threshold tolerance
times max(1, its initial norm). Log objective and residual. Hitting the iteration
limit is reported explicitly; finite results are not proof of convergence or a
global optimum. Initialization is deterministic from seed/element/factor SHA-256;
unseen training-element rows start at zero and remain zero.

## Missing entries and scoring limits

Alpha supplies a weak zero-target penalty for **unobserved pair associations**.
This is an implicit-feedback modeling assumption, not a verified-negative
compound label or an unbiased PU-risk estimator. It can suppress real unobserved
associations and must be disclosed. Lambda controls factor magnitude. The model
is a custom weighted SymNMF comparator; it does not reproduce either the Seko
model or the optimizers/results of the references below.

Every in-scope candidate is scored using its pair dot product. A pair of known
training elements is scoreable even when the pair itself was never observed.
If either element was absent from training, return zero with an explicit
`unseen_element_zero` coverage flag. Do not drop the candidate. Zero is a
conservative fallback, not a chemical-impossibility claim. Scores are association
scores, not probabilities; do not clamp them or interpret them as synthesis odds.

All stoichiometries in a system receive identical learned scores. Use the existing
v1 tie hash and formula fallback, and report tied-score/system counts in any real
evaluation. This prototype tests association transfer, not within-system
stoichiometry discrimination. Rank and factor fitting may encode popularity;
a future evaluation must include the original popularity comparator.

## Isolation and future model-selection rules

Fit accepts training formulas and explicit configuration only. It cannot receive
candidate membership, source IDs, outer evaluation labels or a full-data cache.
Vocabulary is predefined; pair counts, scaling, initialization's active rows,
factors and convergence all come from the training set. Scoring never refits.

For this feasibility gate, perform **no hyperparameter search** and inspect no
new real-data rankings. If proceeding to scientific evaluation, first freeze a
separate protocol carrying the existing two holdout designs and all three label
policies. Use the fixed settings above initially unless a prospectively documented
training-only development check identifies a numerical problem.

Any later tuning must occur inside each outer training-positive population:
construct deterministic inner holdouts of positives, with system grouping for
system-transfer selection; exclude every outer candidate and label from fitting,
normalization, inner candidate construction and selection. Explicitly define the
inner unlabelled/reference pool and objective before tuning; these are not
invented here. No tuning is authorized until that inner protocol exists. Refit
from scratch on the complete outer training set after inner selection. Equal
outer candidate populations, unchanged reference methods, exact split verification
and all label policies remain required.

## Feasibility tests and decision criteria

Use artificial ternary formulas only. Test:

- objective and gradient against hand-calculated and finite-difference cases;
- nonnegative finite factors, nonincreasing accepted objective and explicit stops;
- deterministic fitting after input permutation and exact same-environment reruns;
- complete finite candidate coverage, unseen known-element pairs, cold elements,
  canonical duplicate rejection and within-system ties;
- invariance of fitted state to candidate order, added candidates and changed
  evaluator labels; scoring must not mutate factors;
- full fit → ranking → PU metrics on a small synthetic holdout, with no scientific
  performance claim or requirement to beat a baseline on invented labels;
- an artificial size check with 4,288 training and 9,293 candidate compositions,
  reporting cold fitting time, a warm fit, ranking time, allocation and termination.

A go decision means the implementation is numerically checked, covers all
candidates, reproduces and has a practical measured cost. It authorizes preparing
a bounded scientific evaluation, not a claim of useful recovery. If numerical
checks fail, fix and repeat them before inspecting real rankings. If runtime
exceeds 30 seconds per warm synthetic fit on this machine or memory exceeds
512 MiB in that fit, defer full evaluation pending engineering review. Synthetic
size checks do not predict real convergence or end-to-end evaluation runtime.

Record measured costs and a reasoned go/no-go decision below in a dated follow-up.
Do not adopt the original roadmap's 30-hour estimate without supporting evidence.

## References and implementation provenance

[Kuang, Ding and Park, Symmetric Nonnegative Matrix Factorization for Graph
Clustering (2012)](https://faculty.cc.gatech.edu/~hpark/papers/DaDingParkSDM12.pdf)
provides the symmetric nonnegative factorization family. Our weighted pair-count
objective, chemistry representation, initialization and projected-gradient
implementation are specified above, rather than imported from that paper's code.

[Hu, Koren and Volinsky, Collaborative Filtering for Implicit Feedback Datasets
(2008)](https://yifanhu.net/PUB/cf.pdf) motivates making missing-observation
confidence explicit. The analogy does not establish that materials missing from
a database are negative examples. No upstream implementation or dataset is copied.
