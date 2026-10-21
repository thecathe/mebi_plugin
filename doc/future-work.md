# Future work

Work that is understood well enough to describe, but not under way.

- **Three sections are about cost:** "The solver's own per-step cost",
  "Memory of the saturation estimate" and "Extraction's derivation
  search is unindexed". Jonah chose on 2026-10-11 to accept such costs
  as current limits, and to report a limit they cause rather than chase
  it: like reformulating CADP to reach larger sizes,
  they are orthogonal to the research question (what the plugin can
  decide and prove). None is a bug. Verdicts and proofs are correct
  whenever they finish, and `Qed` checks every proof. "The solver's own
  per-step cost" and "Memory of the saturation estimate" come first: the
  first touches every proof a user runs, the second only very large
  FSMs.
- **"Proofs split into separately checked lemmas"** is a capability
  (@dcastrop's decision 3, `decisions.md`), the one that would reach
  proofs the plugin cannot produce today.
- **The rest** lists smaller possible work, and what was set aside on
  purpose.

`OUTSTANDING.md` lists each item in one line.

## The solver's own per-step cost

**Standing.** Measured, cause unknown. CPU timers around each solver
step (2026-10-11; patch kept locally as `notes/tools/solver-profile.diff`)
separate the plugin *deciding* the next step (building its tactic) from
Rocq *running* that tactic:

| proofs | decision share of `Solve` | decision per step |
|---|---|---|
| `Proc/Test1`..`Test3`, `CCS` | 20-30% | 0.4-0.8ms |
| `Evaluation/Width`, `Layers` | 30-40% | 0.55-0.67ms |
| `Evaluation/Depth` | 65% | 1.5ms |
| CADP `Size1` | 40-80% | 2-8ms |

So deciding is cheap on small terms and ~10× dearer per step on CADP,
whose states carry the whole program text.

**Why it matters.** It is in every `MeBi Sim Solve`, so it would speed
up every proof, including the checked-in ones. It may share a cause with
CADP `Size3`'s proof memory, which is also unexplained: a proof over
`bigstep_norm`'s 644 states was OOM-killed at 8-9GB
(`examples/CADP/MutualExclusionLarge.v`), while `Size2`'s over
`bigstep`'s 772 peaks at 4.4GB. One hypothesis, unprobed: each state
carries the whole program text, so the proof term grows with term size
as well as with steps.

**Not known.** Whether the cost is a constant per term node (then it
only scales with model size) or something that grows within a proof
(lookups or conversions on states, say). That decides whether a fix is
small.

**Where to start.** Rerun the patch on CADP with finer timers inside
`Proof_solver_step` (state lookup, transition lookup, the choice of
answer) and see which one grows with term size. Then compare one
glued `Size1` proof against its normalised counterpart, which has
smaller states.

**Relation to other items.** Replaying a derivation tree in one step
(below) would still make each decision, so this is the larger lever of
the two.

## Memory of the saturation estimate

**Standing.** Cause found; not fixed. `Model.SaturationEstimate` keeps,
for each of an FSM's K silent SCCs, a dense bitset over all K
(`tau_reach`), and another K² bits per label (`weak_of`). `Run Bisim`
and `Sim Begin` compute it after extraction, to choose between whole
and on-demand saturation. `Run FSM` does not. Measured in pure OCaml on
a silent DAG: heap +27, +101 and +402MB at K = 10k, 20k and 40k (×4 per
doubling).

**Where it bites.** Glued CADP has one silent SCC per state (`Size2`:
772 of 772), so glued `Size3` (128,044 states) needs ~4GB for the
estimate on top of the ~4.7GB extracted FSM, and was OOM-killed at 9GB.
CADP sidesteps it with `bigstep_norm` (644 states). Any user model with
~100k or more silent SCCs needs gigabytes for it (`limitations.md`,
"Many silent SCCs").

**What a fix involves.**
- The estimate only needs counts, and the guard only "above the bound
  or not", so it can run in memory linear in K, for example by stopping
  once the bound is passed. That part is small.
- The on-demand bisimilarity check (`scc_moves`, `refine_blocks`) reads
  the same `reach` and `weak_of` sets. A fix to the estimate alone may
  move the OOM there. Sparse sets help when the weak moves are few. When
  they are many, they *are* the saturation's size, which no
  representation avoids.
- It touches the model, so it needs the full proof-suite runs and the
  saturation golden test (`satdiff`).

## Proofs split into separately checked lemmas

**Kind:** *capability* (large). A new proof back end, not a heuristic.

**Standing.** Not started; discussed 2026-10-12. Motivated by CADP
`Size2` glued ≈ layered (`examples/CADP/GluedLayered.v`). It is decided in ~35s, but every proof
attempt ran out of memory *during `Solve`*, before `Qed` was reached.
Both `weak_sim`s and the `weak_bisimilar`, on the nested path, were
OOM-killed at 7GB and at 10GB, and memory grew steadily to the cap. The
mutual path's game has 514,020 pairs and 2,056,080 moves (under `Answers Default`; `Auto` plans 78,202 pairs and 312,808 moves). On a 31GB host both nested and mutual-under-`Auto` ran out of memory at 24GiB, and mutual-under-`Default` was unfinished after 24h at 5.0GiB (`doc/measurements/cadp-large.md`).

**Why one proof cannot simply be cut up.** Today a proof is one `cofix`.
A pair that reaches a pair already under proof closes the cycle with the
coinduction hypothesis, which exists only inside that term. The product
has cycles, so lemmas per state would have to use each other, and Rocq
has no mutual dependency between separately proved lemmas.

**The way round.** Prove bisimilarity through an explicit relation:
- Define R, the product's pairs, as a finite relation. Name each state
  once (`s1 := ...`), so that R is written over names. CADP states carry
  the whole program text.
- In `theories/`, prove once that a weak bisimulation (or simulation)
  containing `(p, q)` gives `weak_bisimilar p q` (or `weak_sim`). It is
  a small fixed `cofix`. `theories/Bisimilarity.v` has no such lemma
  today.
- Show R is a bisimulation, one obligation per pair: each move has an
  answer that lands back in R. Landing in R is a membership check, not
  the coinduction hypothesis, so the obligations are independent. Group
  them into lemmas by block (for example, per glued state) and blocks
  into files.

A `Qed`'d lemma is opaque. Later proofs use only its statement, and
`Require` does not load its body. So peak memory is about one block, and
files compile in parallel. The plugin already computes what this needs:
the partition, and the pairs and answers that the mutual path uses.

**What it does not fix.** The total work is still one derivation per
move (about 2M at `Size2`), so time stays large, although it is spread
over files. The statement of R and the per-block lemmas add to the
environment.

**Relation to other items.** It is complementary to "The solver's own
per-step cost", which makes each step cheaper. It is independent of
"Proving one state per silent SCC" (set aside, below): R relates states,
not SCCs.

## Extraction's derivation search is unindexed

**Standing.** Cause found 2026-10-13; not fixed. On the ABP with a data
domain of n values, extraction's time per state grows with n: 26, 37, 49,
62 and 77ms for n = 1..5. Within one run it does *not* grow with the
states already seen (at n = 5 it falls from 101ms a state in the first
fifth to 59ms in the last), and no state is visited twice. So it is not
the bug the earlier question feared.

**Cause.** All the time is in finding a state's transitions
(`collect_valid_constructors`). For each state it tries every
constructor and every branch of the source term by unification: 1,753
`w_unify` attempts a state at n = 1, about 600 more for each extra datum,
to find ~2.7 transitions. Roughly half fail outright, and most successes
belong to derivations that fail further down. Each attempt costs about the
same (6-9µs in `w_unify`, ~45% of the time; the rest scales with the
attempts too). `sums n` gives the sender, receiver and media n
alternatives each, hence the slope.

**What a fix involves.** Fewer attempts: skip a constructor whose
conclusion's head cannot match the source term's, before unifying (an
index on head symbols), and prune a premise's branches the same way. It
touches the proof solver's view of derivations, so it needs the full
proof-suite runs. How much it would save is unmeasured. The measurement
patch is kept locally (`notes/tools/extraction-profile.diff`).

## Re-running the large CADP proofs

**Done 2026-10-15/17, on a 31GB host; the results are in
`doc/measurements/cadp-large.md`.** The two three-process proofs
(`ThreeProcessesMutex.v`, `ThreeProcessesFifo.v`) finish there, at 13.4 and
17.8GiB peak, and take the same steps under `Answers Auto` and `Default`: the
machine, not the policy, is what changed. Glued ≈ layered
(`TwoProcessesGluedLayered.v`) does not finish: out of memory at 24GiB,
nested after 2h05m and mutual (with `Bounds Game`) under `Auto` after 16h;
and unfinished after 24h mutual under `Default`, at only 5.0GiB. Under
`Default` the mutual game is the 14GB host's (514,020 pairs, 2,056,080
moves, `Begin` 82s, memory flat at ~2.2GiB), under `Auto` it is 78,202 pairs
and 312,808 moves with a `Begin` of 4,489s and much more memory: so the
answer policy, not the host, accounts for that difference. The proof
headers, `OUTSTANDING.md`, `examples/README.md`, `decide-vs-prove.md`,
`limitations.md` and decision 3 were updated from these. The commands are
in `bench/README.md` (`-s cadp-large`, `-s cadp-huge`, with `-M` and `-a`).

**What remains.**
- **Glued ≈ layered under `Answers Default` for longer than 24h.** It was
  stopped at 24h with no `Solved` line and at 5.0GiB, far below the cap, so
  time is its limit and how long is unknown. The solver prints nothing before
  it ends, so a run cannot say how far it got.
- **Why `Auto` plans a game with 6.6 times fewer pairs that takes 55 times as
  long to set up and uses far more memory.** The plan is chosen by
  prediction (`Model.Product.estimate` and the answer planner); this proof
  is a case where the cheapest predicted plan is not the cheapest run. An
  open *optimization* question.
- **Glued ≈ layered under `Auto` above 24GiB**, if a host has room: the
  proof sat at 16.7GiB for ~4.6h and then climbed, so it needs more than
  24GiB, by an unknown amount. Less promising than the first item. Since
  2026-10-16 `Bounds Memory` stops a command at 90% of a cgroup cap by
  default (about 21.6GiB under `-M 24G`), so set it higher, or to `0`, in the
  working copy for this run, and rely on the cap.
- **`bench/lib.sh` needs GNU `time` at `/usr/bin/time`**, and fails
  at once without it ("Failed to find executable /usr/bin/time", exit 1, 0
  errors, easily mistaken for a result). NixOS has none. The re-run
  used `nix-shell -p time --run '...'` with the line changed to
  `"$(type -P time)"`, as a local edit that is not committed. It is documented
  in `bench/README.md` ("Requirements") rather than fixed in code: hosts with
  `/usr/bin/time` work as they are, and a `PATH` fallback has not been tried
  on them.

## Ideas from chess engines

**Initial ideas only (2026-10-19), none investigated.** Each needs
measuring against the plugin's real costs before any work starts, and
some may turn out not to apply. Jonah was pointed at
[chessprogramming.org](https://www.chessprogramming.org/) as a source of
techniques that make search competitive rather than brute force: compact
encodings, and the tricks such encodings allow. The plan is to take this
up once bugs are few, but some of it (perft especially) also helps find
them, and running large examples in reasonable time and memory exposes
problems too.

How each technique might map onto the plugin:

- **Perft** (counting the positions reachable to a depth, to check a move
  generator against known totals). The counterpart is counting
  extraction's states and transitions, and the game's pairs, against an
  independent implementation: a regression check for extraction that
  `Test.v` lacks. The external feedback's user did this informally, with
  a 100-line checker of their own (`feedback-2026-10-15.md`). Likely the
  first to try, as it tests rather than optimises.
- **Transposition tables** (caching positions already searched).
  Extraction asks the same premise question, the relation, source and
  label, more than once; caching the answers would cut repeated work, and
  is the complete form of the repeat cut-off for self-recursive rules
  (`OUTSTANDING.md`, Bugs). In the solver: pairs already proved, or game
  positions already costed.
- **Proof-number search** (best-first search of AND/OR trees, from chess
  endgame solving). The bisimulation game is such a tree: every attacker
  move must be answered (AND), and one answer is enough (OR). It is a
  principled way to choose which goal to expand next; today's answer
  policies (`Answers Auto`) use cost estimates.
- **Move ordering, killer moves** (trying likely refutations first). The
  counterpart is answer ordering: the answer that worked for a similar
  pair first.
- **Bitboards** (sets of squares as machine words). States could be dense
  integers per FSM, with state sets and partitions as bitsets, for
  saturation, partition refinement and the product game. Encodings are
  already integers, but sets of them are balanced trees.
- **Zobrist hashing and hash-consing** (cheap incremental hashes; one
  copy of each term). Pointer-equal terms would make term equality and
  lookup cheap: extraction's search is unification-heavy, and the solver
  finds a goal's states by looking terms up (the term-equality question,
  `ASSISTED-CHANGES.md`, 2026-09-28).
- **Precomputed lookup tables** ("magic" tables for move generation).
  Indexing constructors by the head symbol of their source would avoid
  trying each by unification: "Extraction's derivation search is
  unindexed", above.
- **Make/unmake** (updating a position in place instead of copying it).
  The encoding is rebuilt by every command; incremental updates across
  commands, or of saturation, may matter on large systems.
- **Nodes per second** as the standard measure. The counterparts are
  states per second for extraction and steps per second for the solver,
  tracked per build, as `bench/compare.sh` begins to.

## Step messages: finish the stubs, build them lazily, then a script

**Standing.** Agreed in principle 2026-10-21; not started. Each tactic the
solver builds carries a message (`Tactic.t`, `src/proof_solver_tactic.ml`),
emitted at `Info` when the step's chain is applied (`Tactic.unpack`): the
plugin's counterpart of `info_auto` (`trivial` already switches to Rocq's own
`info_trivial` output when `Info` is on). Some messages print a placeholder or
say less than what is applied. Four phases, in this order; 1 and 2 go
together.

**1. Finish the stubbed printers** (*bug fix* / tooling, small).
- `Strfy.econstr_bindings` (`lib/rocq_tools/rocq_monad_strfy.ml`) returns the
  literal strings `"TODO: implicit bindings"` and `"TODO: explicit bindings"`,
  with the intended code commented out beside them. Its only user is the
  `Debug` log in `Tacs.apply_constructor`, so even `Debug` shows nothing. Implement
  both, and show the bindings in the `constructor` message at `Info`:
  `econstructor i with (x := t) ...` (the code applies `econstructor`, and the
  message says `constructor`). Test anonymous binders: `Constructor_bindings.get_quantified_hyp`
  maps them to `AnonHyp 0` (FIXME), which would print as `(0 := t)` and not replay.
- The handler for `InvalidCheckUpdatedCtx` prints `"TODO: substls"` and
  `"TODO: ctx_tys"` (`lib/rocq_tools/rocq_monad_utils.ml`). Print them.
- Look for others when starting: `grep -n '"TODO' src lib`.
- Messages do not change which tactics run, so every count in `CLAUDE.md` is
  the check. There is no assertion on message text; read the `Info` output of
  one proof by hand, or grep it in a `bench` script.

**2. Build messages lazily** (*optimization*, small).
- Today `Tactic.create ~msg:(Printf.sprintf "exists %s" (Strfy.econstr t))`
  runs the printer when the tactic is *built*, whether or not `Info` is on, because
  the argument is evaluated first. `Logger.thing` (`lib/utils/logger.ml`)
  names this hazard in its own comment and guards against it; tactic messages
  have no such guard.
- **Measured 2026-10-21** (Rocq's printer on normalised CADP initial states,
  200 copies printed per run, `Time Print`): **0.28 ms** (1 process, 1.5KB),
  **0.58 ms** (2 processes, 3.1KB), **1.0 ms** (3 processes, 4.9KB), about
  0.2 ms per KB. The one large eager print today is `exists`'s (`ex_intro`),
  once per answered move, which is every 9-11 steps on CADP: **0.03-0.1 ms a
  step, under 5% of its 2-8 ms decision cost**. So the current cost is small, and it
  does not explain the CADP per-step cost in "The solver's own per-step
  cost" (an earlier suggestion that it might is withdrawn).
- Phase 1 changes that: it prints every binding at every constructor
  application, one per step in `ApplyConstructors`, and a binding can be most
  of the state. Up to ~0.3-1 ms a step on CADP (estimated, not measured),
  against a 2-8 ms decision. That is why the laziness goes with phase 1.
- Change: `Tac.msg : (Output.Kind.t * string Lazy.t) option`, and `Tactic.create`
  takes the message as a thunk, forced in `to_string_opt` only when
  `Logger.is_enabled k`. 26 sites (24 in `proof_solver_tactics.ml`, 2 in
  `proof_solver_step.ml`). Only those that print a term need it (`exists`,
  `apply`, `eapply`, the bindings); the rest are cheap and may be converted for
  uniformity. Keep side effects (`new_cofix_name`) outside the thunk. `Strfy`
  reads the monad's context when it runs, now the same step; the terms are ground
  states, so it makes no difference.
- With `Info` on (the default) the cost is paid, by design.
- Measure with the solver-profile patch (`notes/tools/solver-profile.diff`,
  per-step CPU time) on the CADP default-suite files. Wall time of
  `bench/proofs.sh -s default` cannot show 1-5%: the same suite varied by
  more than that between runs on 2026-10-19.

**3. Exact messages** (*bug fix*, deferred). Make each message say what is
applied. Inventory (about 25 sites): `constructor` (bindings; `econstructor`;
two unprinted post-steps, `move_premises_last` and `fix_premise_witnesses`, both
no-ops on every checked-in example), `exists` (the `split` after it),
`simpl` (`simpl in *`), `unfold` (prints the kernel name), `mutual_cofix` (the
types are not printed), and the descriptive ones with no vernacular form:
the refute family, `(prove negated premise)`, `(prove bounded universal premise)`,
`exact (premise proof)` (the term is not printed), `(to all goals)`.

**4. A proof script written to a file** (*new feature*: agree before code).
An output setting in the style of `DumpResults` that writes the proof as the
solver builds it, for reuse without running the plugin again. It needs phase 3 for
every tactic it emits: a file that does not replay is not reusable. So the script
should be a separate rendering (a `script` thunk beside `msg`), not scraped from
`Info`. A step with no vernacular form is written as a marked comment and the
file says it is incomplete; the alternatives are `exact <term>` or a plugin
tactic (the script then needs the plugin). It cannot edit the editor's buffer.
Test by replaying: the bench harness recompiles every checked-in proof from its
emitted script. Estimates, rough: phase 1 plus 2 about a day; phase 3 for the
common-case tactics (`constructor`, `exists`/`split`, `mutual_cofix`, `unfold`,
`simpl`) 1-2 days, for all 2-4; phase 4 on top 2-3.

## Smaller possible work

**Evaluation** (detail in Jonah's local notes 10 and 12)
- **Compare with CADP and mCRL2**: verdicts and cost on the same models.
  Neither tool is installed; CADP needs a licence.
- **Scale the evaluation levers further** (`bench/proofs.sh -s
  eval-large`). Stopped at 128 layers (Qed alone would take on the order
  of 15 min) and at depth K = 32 (~260k steps extrapolated).

**Optimization**
- **Replay a derivation tree in one solver step** (*optimization*,
  measure first). Today each step applies one constructor of a
  transition's derivation tree, in preorder
  (`Proof_solver_step.handle_appconstrs_update_args`), so a layer adds 14
  steps (`Layers.v`). Why it is not simple batching:
  - each application reads the goal the previous one left;
  - premises open sibling goals, which a step cannot see, because steps
    run focused on the first goal.

  So it would be one tactic inspecting goals as it runs. It would save only
  the solver's per-step overhead: the proof term, and so `Qed`, would be
  unchanged, and at depth `Qed` dominates (`limitations.md`, "Deep
  derivations"). Every checked-in bound
  would change.

  Measured 2026-10-11 (CPU time inside `Solve`, default and `eval`
  suites): the plugin's own decision of what to do next is 20-30% on
  `Proc` and the CCS laws, 40-80% on CADP and 65% on `Depth`. Rocq
  running the chosen tactic (with `Declare.Proof.by`'s bookkeeping) is the
  rest. Replay would still make each decision, so it could save at most
  part of the tactic share. The decision cost ("The solver's own
  per-step cost", above) looks like the larger lever.
- **`Auto` mis-estimate** (*optimization*, small). On `LawProofs.tau1`,
  `Auto` picks nested (42 steps) where mutual takes 29. A data point for
  `Product.estimate`, if it is revisited.

**Reusable theory** (agreed 2026-10-11: machinery a user could reuse
goes into `theories/` once two examples use it, which keeps `examples/`
minimal): nothing open. The last item, trace preservation, became
`theories/Traces.v` on 2026-10-13.

**Tooling**
- **`bench/ocaml/fixtures/` is stale.** Last regenerated 2026-10-10.
  `bench/ocaml/make-fixtures.sh` now writes 47 fixtures, several under new
  names (CADP was restructured 2026-10-13) and several with new contents.
  Regenerating and committing them changes what the OCaml benchmarks
  measure, so it is a choice, not a fix. Found 2026-10-19.

**Examples**
- `examples/Bisimilarity/_nat_streams.v`: unfinished, kept as real work,
  status unclear.
- CADP `Size2`/`Size3` proofs: see `OUTSTANDING.md`.

## Set aside (deliberately)

Kept so they are not rediscovered as new. Each could be reopened, with the
reason in mind.

- **Proving one state per silent SCC** (abandoned 2026-10-03): unsound
  inside a coinduction, counterexample `CircularTransfer`.
- **`ReModel` unification instead of lookup** (A1): measured, cannot miss
  in current usage. Its value would be goals with an unknown state, closed
  as "give the witness by hand" (`limitations.md`, "Goal shapes").
- **Inversion tie-break options B and C**: closed unbuilt; residual
  sterile steps measured at zero after options A and D′.
- **Divergence-sensitive equivalences**: out of scope for the current
  definitions.
- **Module lists** (`_CoqProject`, `.mlpack`, dune) are still maintained
  by hand. A drift is caught by `scripts/check_module_lists.py` (CI)
  rather than prevented.
- **odoc warnings**: 72 remain, all `@raise` tags naming stdlib or Rocq
  exceptions, which odoc cannot resolve. Accepted.
