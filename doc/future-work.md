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
step (2026-10-11; a throwaway patch, not kept in the repository)
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
patch was a throwaway and is not kept in the repository.

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

**Standing.** Agreed 2026-10-21; not started. **Phases 1 and 2 are next up**
(`OUTSTANDING.md`); phases 3 and 4 are future work. Each tactic the
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
- **Memory, measured 2026-10-21** (the same states, 200, 1,000 and 5,000
  separate `Print` commands, `OCAMLRUNPARAM=v=0x400`): each print allocates
  **2.5-2.7MB, about 500x the 4.9KB of output**, of which ~170KB is promoted to
  the major heap. Peak RSS did not grow with the number of prints (233MB for
  none, 365MB for 1,000, 277MB for 5,000): garbage waiting for a major
  collection, not retention. The string is the small part; a thunk skips the
  whole printing pipeline and holds a few pointers to data that already
  exists. With a print at every constructor step, a direct 11,128-step CADP
  proof would churn up to ~30GB instead of ~3GB (an upper bound).
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
- Measure with per-step CPU timers inside the solver (the throwaway patch
  behind "The solver's own per-step cost" above, not kept in the repository)
  on the CADP default-suite files. Wall time of
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

**Evaluation**
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

**`MeBi Draw`** (`MeBi Help Draw`; measurements in
`doc/measurements/draw-layout-time.md`)
- **Direction agreed with the author, 2026-11-01.** The standalone engine
  (LuaTeX, nothing else installed) stays the default, and is to be improved
  until it does not need Graphviz. Graphviz becomes an *optional* engine,
  used when `dot` is found. It can be offered but not bundled: as an
  optional opam dependency (`depopts: conf-graphviz`, which asks the system
  package manager) and in the repository's Nix flake. The drawing side is
  to become a second plugin in the same package, `rocq-mebi.graph`, loaded
  on request, with the option of folding it back into the main plugin.
  **Details deferred to a later session:** the hooks the core would need (a
  registry for reset callbacks and one for help topics, and what
  `Decode.Diagram` needs exported), and what `make` does about it.
- **Standalone parity: what is left.** Styling is done (2026-11-01: bigger
  text, tighter padding, rounder corners; `Draw_style.default`). So is
  where a label sits, as far as the layered layout allows (2026-11-02): each
  label is a node of the layout (`a -> e -> b`; `MeBi Config Draw Labels
  OnEdge`, the default), which keeps room for it and removes the overlaps,
  at 2.2 times the layout time at 31 states, 2.6 at 50, 3.5 at 75 and 4.1
  at 100 (`Labels Beside` is the old placement). The other way, laying out
  and routing first and putting the label on the middle of the finished
  curve, is the author's rule and is simple once something routes the edge
  (Graphviz does; LuaTeX's layered layout does not expose it). Done the same
  day: the picture's shape (`MeBi Config Draw Direction Right` grows the
  layout to the right, a landscape picture for a slide) and a back arrow's
  label half way. For the latter, the Graphviz rule needed a first pass to
  read the ranks; in the standalone engine it does not, as the longest path
  the arrow closes is computed from the diagram (`Draw.back_arrows`, then
  half of that many layers on each side of the label node, `minimum
  layers`). What made it work, and what did not: an arrow back is laid out
  from its target to its source, which the layout reads as the direction of
  the arrow, so the arrowhead cannot be a tip of those arrows (`<-` made the
  layout put the label above the target, as the first attempt showed); it is
  a decoration (`postaction` with `decorations.markings`,
  `\arrowreversed`) of the first half, which the layout does not see.
  `minimum layers` alone, on the arrow as it was, made it worse: only the
  half that closes the cycle is reversed, so the label stays one layer from
  the source. Colour per kind of label is done too (below). The look was
  made tighter, bolder and rounder the same day (`Layout` 10 mm down and 30 mm
  right, `Edge` `thick` with `rounded corners=10pt`, `Label` `inner sep=2.5pt`),
  and both halves of an arrow back got `weight=0.2`, which keeps the path it
  closes straight. The layered layout has one router, polylines, so the arrows
  are polylines with rounded corners and not the splines the Graphviz pictures
  had; splines need Graphviz (the optional engine), or Béziers drawn after the
  layout, which would lose the layout's routing around nodes for long arrows.
  Left: the Graphviz engine.
- **Graphviz, the actual Graphviz** (clarified by the author, 2026-11-02: they
  actively want Graphviz's own behaviour, its splines and its layout; what they
  dropped was my *re-drawing* of `dot`'s output in TikZ, whose kinks and
  detached arrowheads were that conversion's). **Done the same day, opt-in:**
  `MeBi Config Draw Engine Graphviz` (`Draw_dot` writes the DOT from the
  `Draw.t` the plugin already builds, `Draw_output.render_dot` runs `dot`), and
  `scripts/dump2dot.py` does the same from a plain-text dump, outside the
  plugin. Built so that nobody who does not ask for it meets it: LuaTeX stays the
  default; nothing is installed or needed; `dot` runs only for a PDF or a PNG, as
  a child process with the time limit; a missing, failing or slow `dot` is a
  warning and the `.dot` is kept. Left: Graphviz's own settings (`ranksep`,
  `nodesep`, the font) are fixed, not configurable (the `.dot` can be edited and
  drawn by hand, and the script has them as options); the text is in Graphviz's
  font, not the document's, and the picture cannot be restyled from LaTeX; the
  TikZ styles do not apply to it; and it was checked with Graphviz 15.1.1 only.
  If the LuaTeX engine is later dropped for this one, `Style`, `Layout` and
  `TwoWay` go with it.
- **One LTS drawn over another** (*new capability*, so to be agreed first;
  asked for as a picture, 2026-11-02, not as a feature). For the talk the author
  wanted `Simple.v`'s upgraded machine (coffee and tea) drawn so that the
  coffee-only machine is a visual subset of it, the tea branch above, as an
  overlay. Done by hand, once, on the `.dot` (ordering groups, a heavier coffee
  chain, a label's margin and layer); the coffee part then equals the initial
  layout to 0.000 points, and a companion picture with the tea invisible, on the
  same canvas, gives the "before" to flip from (devlog, `draw.md` 6.16). A
  plugin facility would take a base LTS and an extended one and pin the shared
  part's layout; the hand-made version shows what it needs (a vertical order per
  layer, Idle level with the base's row, no layer widened by the extra labels)
  and that it is fiddly in `dot`.
- **The Graphviz look's two measured constants** (small). The room that makes the
  line to an arrowhead as long as the other (`Draw_dot.head_allowance`, 11
  units) was measured for `arrowsize` 0.8, `penwidth` 1.4 and Graphviz 15.1.0,
  and the label cell's padding (1) trades roundness of the lines against how
  close the text is to them. If the engine's spacing or pen becomes
  configurable, derive the first from them (the head is `10 * arrowsize`, and the
  tip stops about `1.5 * penwidth + 0.3` short of its node) instead of keeping a
  number.
- **A Graphviz engine that re-draws in TikZ** (dropped; see above). **Prototyped 2026-11-02** (a
  throwaway script, not in the plugin; the devlog has it): from the picture the
  plugin writes it takes the states, arrows, kinds and labels; measures each
  state and label with TeX in the picture's own styles (one `lualatex` run), so
  that `dot`'s boxes are TeX's; writes DOT with each label a node of the layout
  (`a -> l -> b`, the forward chain weighted, an arrow back laid out target to
  source with `minlen` the half-length the plugin already computes); runs
  `dot -Tplain`; and draws each piece as `dot` routed it (a Bézier) in the
  plugin's own named styles, the label on top at the node's centre. On the
  five-state cycle and the 18-state coffee machine, down and right, it gives
  smooth splines, a straight forward chain, **uniform visible lines** (`dot`'s
  `ranksep` is border to border: the silent step's tau is no longer a long
  dashed line) and the arrow back's label half way; about 1.2 to 1.7 s in all,
  most of it the two `lualatex` runs, `dot` itself a few ms. Not covered by the
  prototype, and what a real engine needs: a state's arrow to itself, merged
  labels, a terminal state, the incomplete caption, the bounds (`dot` is fast,
  so the state bound could rise: measured 5.8 s at 300 states and no result at
  1,000 with every label a node, 2026-11-01), a way to say the spacing (`Layout`
  is LuaTeX's; `ranksep` and `nodesep` would be new settings), and a fallback to
  the LuaTeX engine when `dot` is absent, fails or is killed at the time limit.
  **Estimate for the real thing, in OCaml in `lib/draw` (no `rocq-runtime`):**
  the DOT writer about 80 lines, the TeX measurement about 60 (or an estimate
  from the text's length, cruder: arrowheads would not touch their boxes), the
  `-Tplain` parser about 50, the TikZ emitter about 120, then the wiring
  (`MeBi Config Draw Engine Auto | LuaTeX | Graphviz`, help, README, the fallback)
  and tests (the parser and emitter on captured `dot` output, a compile test that
  skips without `dot`), and the packaging (`depopts: conf-graphviz`, the Nix
  flake). Roughly 350 to 450 lines of code and 200 of tests: about a day of
  work, in a session or two, plus a review of what the author wants from the
  settings. It adds a runtime program, not an install-time dependency, and the
  licence note of the 2026-11-01 entry stands. Old notes on the rule for a back
  edge, below, were for this engine. Written for Graphviz, the
  rule for a back edge (found by a depth-first search from the initial
  state) is: lay it out reversed, and pin its label half way with `minlen`
  after a first pass that reads the ranks off the y coordinates. The author
  prefers this shape (the edge down the side, entering the target from
  below) to the one with side ports (`tailport`/`headport=e`), which was
  tried and gives a cleaner exit but a harder edge to read; flipping alone
  leaves the label at the top, the first pass is what centres it. For a
  TikZ picture drawn from `dot -Tplain`, route first and place the label at
  half the curve's arc length. `dot2tex` is the existing converter: with
  `--preproc` it needs `preview.sty` (absent from this host's TeX Live), and
  it cannot put a label on the middle of an edge.
- **Colour by kind of label** (done 2026-11-02, flagged first and agreed:
  `MeBi Config Draw Kind "<Kind>" "<colour>"` and `Kind Default "<colour>"`).
  The colours are explicit, as the author asked: nothing is coloured unless
  set, and no palette is cycled over the kinds (considered, and set aside).
  A kind is the first word of the printed label; the arrow, its label's text
  and a frame at 40% of the colour are coloured; the default colour is for
  the kinds with none of their own; an arrow of several kinds has none, and
  a silent step is not coloured by kind. Left: a kind from the term's
  constructor rather than the printed text (a label that is not `Word
  args`, such as `(a, b)`, has no kind a name can be given for); the frame
  and its rounding are fixed (`40%` and `5pt`), not configurable.
- **A label's second half.** A label is the term printed, tidied (no outer
  parentheses, no `Some` when every label has one). When a colour already
  says `Insert`, only the argument (`ten`) would do; that needs the kind
  above.
- **A state's number in its box,** to cross-reference the plain-text dump
  (they share a numbering, `Decode.Diagram`), if wanted: a `State` style
  cannot add it, as that is content, not look.
- **Labels on the arrow, not beside it** (done 2026-11-02 as label nodes,
  see "Standalone parity"). The author asked for each label centred on its
  arrow, white behind it, with an optional light frame. TikZ's `pos` runs
  along an arrow's *last stretch* only, and the layered layout routes an
  arrow as several, so no style could do it (tried 2026-11-01: `auto`
  dropped, `midway` added, no change); a label node can, and the `Label`
  style (white fill, `draw=gray!50`) applies to it.
- **Layout time with label nodes** grows faster than the size (see the
  measurements): the draw bound and its time limit may want a second look
  for `OnEdge`. A bigger bound with `Labels Beside` stays cheaper.

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

**Notifications** (`MeBi Config Notify`, `lib/utils/notify.ml`)
- **macOS and Windows.** Only `notify-send` is run, so only a Linux (or other
  freedesktop) desktop gets a notification. macOS has `osascript -e 'display
  notification ...'` with nothing to install, and would be a few lines, but it
  cannot be tried here: the flake lists `aarch64-darwin` as untested for the
  same reason.
- **A terminal bell, for `rocq compile` in a terminal.** Left out on purpose. It
  is written to stdout or stderr, and under vsrocq (where the plugin is used
  in practice) stdout may be the language server's protocol channel, where a
  stray `\a` could do harm; it would also tell the user nothing in an editor.
  Worth adding only if it is written to a terminal known to be one
  (`Unix.isatty`).
- **The command's own memory.** What is reported is the process's peak as
  `Memory_guard.check` saw it, and what it held at the start; the command's
  own use is not recoverable from the two. OCaml keeps memory it has freed, so
  a command that reuses it never raises the peak (the figure under-counts),
  and one that lets an earlier command's data be collected can lower it.
  `Gc.stat`'s live words would be exact for the OCaml heap, but a full
  major scan of a large heap takes seconds, and Rocq's own memory is not in it.
- **Peak by the kernel's counter (`VmHWM`), rejected.** Exact, and it sees
  what the plugin's loops do not check (Rocq's kernel in `Qed`). But the only
  way to make it per command is to reset it (`echo 5 > /proc/self/clear_refs`),
  and that also resets the peak the operating system reports when the process
  exits: measured 2026-11-02, a process that peaked at 420MB exited reporting
  12MB. `bench/lib.sh` takes its figures from `/usr/bin/time`'s `%M`, so every
  benchmark would under-report whenever notifications were on. Reading it
  without resetting gives the whole process's peak so far, not the command's.
- **Wall-clock time.** The duration is `Unix.gettimeofday`. On a laptop that
  suspends mid-run it would probably include the sleep, and a clock step
  would change it. Not measured. A monotonic clock (OCaml's stdlib has none
  that is portable) is the fix if it matters.
- **Announce a proof when it is closed.** `Qed` is Rocq's command, not the
  plugin's, so it is not announced; the last `MeBi Sim Solve` is.

## Set aside (deliberately)

Kept so they are not rediscovered as new. Each could be reopened, with the
reason in mind.

- **Proving one state per silent SCC** (abandoned 2026-10-03): unsound
  inside a coinduction, counterexample `CircularTransfer`.
- **`ReModel` unification instead of lookup**: measured, cannot miss
  in current usage. Its value would be goals with an unknown state, closed
  as "give the witness by hand" (`limitations.md`, "Goal shapes").
- **Further inversion tie-break variants**: closed unbuilt; sterile steps
  were measured at zero after the hypothesis-order fix and the refutation
  of dead steps (both 2026-10-02).
- **Divergence-sensitive equivalences**: out of scope for the current
  definitions.
- **Module lists** (`_CoqProject`, `.mlpack`, dune) are still maintained
  by hand. A drift is caught by `scripts/check_module_lists.py` (CI)
  rather than prevented.
- **odoc warnings**: 72 remain, all `@raise` tags naming stdlib or Rocq
  exceptions, which odoc cannot resolve. Accepted.
