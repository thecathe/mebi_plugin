# Limitations

What MeBi cannot do today, as it behaves now. None is a bug: a verdict
or proof the plugin gives is correct, and `Qed` checks every proof. Where
a limit is pinned, a test in `test/rocq/Test.v` fails on purpose (`KNOWN
LIMIT` / `KNOWN WRONG`), so lifting the limit turns the pin into a
positive test. What could be done about the cost limits is in
`future-work.md`.

Each is current behaviour. Where pinned, a test in `test/rocq/Test.v`
fails on purpose (`KNOWN LIMIT` / `KNOWN WRONG`), so lifting the limit
turns the pin into a positive test.

**Extraction (building the LTS)**
- **Undecidable premises are assumed** (*limit*, pinned `KNOWN WRONG`:
  `UndecidedPremise`, `GeneralPremises`). Examples: an equation MeBi
  cannot decide, an opaque function or axiom with no user tactic, or a
  proof search cut off by `MeBi Config Premise Depth` (default 16). The
  constructor is then applied as if the premise held, with a warning. A
  `Run Bisim` verdict on such an LTS may be wrong; a proof cannot be,
  because `Qed` checks every premise. Seen 2026-10-10:
  `DepthLarge.v` at K = 16 needs the depth raised.
- **LTS premises whose source nothing determines** find only some of their
  steps (*limit*, warned; pinned `OutputPremises.open_u`/`open_ur`).
- **A premise that matches on an argument nothing fixes** (`match x with
  ...` for an `x` only the conclusion mentions) is undecided:
  `LTS_Incomplete` (*limit*, pinned `ExternalFeedback`). A `match` on the
  source term works, and so does `In x (f p)` with `f` computable.
  Enumerating the matched argument's constructors would be a new
  *capability* (small). From external feedback
  (`feedback-2026-10-15.md`, item 3).
- **A guard does not stop recursion through a step premise** (*limit*,
  pinned `ExternalFeedback.step_u`). In `n < 5 -> step (up (S n)) l q ->
  step (up n) l q`, the guard is closed but decided only after the step
  premise is explored, so extraction explores `up 6`, `up 7`, ... until
  the cut-off for such premises (`Premise Depth` levels), and the LTS is
  reported incomplete though it is finite. Before 2026-10-19 it ran away.
  Deciding closed premises before exploring step premises would lift it
  (*bug fix*, small; it changes what extraction explores first, so every
  suite would need re-running). Found 2026-10-19.
- **Self-referential "collapsing" definitions** with a silent collapse
  (B1) are infinite with no finite quotient, and are refused at the state
  bound (*limit*, pinned `Collapsing`). Guarded variants work.
- **LTSs with parameters** are refused (`LTS_Has_Parameters`; *limit*,
  pinned `ParameterisedLTS`). This rules out an LTS generic in its label
  type, or one defined in a `Section`. Workaround: fix the values in a
  module (`examples/Evaluation/Depth.v`). Cheaper (2026-10-19): a
  one-constructor wrapper whose premise is the applied relation,
  `wrap3 n l m : countLTS 3 n l m -> wrapped3 n l m` (pinned
  `ParameterisedLTS.wrapped3`). Its premise is decided by the proof
  search, so derivations deeper than `Premise Depth` need it raised.
  Making this work would be a new
  *capability* (medium). Sketch:
  - accept a term (`constr`) where an LTS is named;
  - instantiate the parameters in the constructor types (`mind_nf_lc`);
  - apply them wherever extraction and the proof solver rebuild the LTS
    term.
- **Size.** Extraction costs ~0.01-0.07MB per state. Its time per state
  grows with the number of alternatives in the source term, because it
  tries each by unification (`future-work.md`, "Extraction's derivation
  search is unindexed"); on the ABP-with-data series total time is
  roughly quadratic in the data domain. Whole saturation is
  refused above `Bounds Saturation` (default 1M weak actions;
  `Saturation_Too_Large`). Above that, `Run Bisim` and `Sim Begin`
  saturate on demand and decide on the silent-SCC quotient.
- **Many silent SCCs.** `Run Bisim` and `Sim Begin` need memory
  quadratic in an FSM's silent SCCs, whatever the saturation bound
  (~0.6GB at 50k SCCs, ~4GB at 128k; glued CADP `Size3` was OOM-killed
  at 9GB). `Run FSM` is not affected. Accepted as a limit for now
  (`future-work.md`, "Memory of the saturation estimate").

**Goals and proofs**
- **Goal shapes** (*limit*, pinned `GoalShapes`). Only `weak_sim` and
  `weak_bisimilar` goals between closed terms are accepted.
  - **Open terms** are refused: a law for every `p` cannot be started.
  - **Local names** are not found, because `Begin` reads terms in the
    global environment.
  - **An `exists` goal** needs its witness given by hand (`exists t.`).

  Witness search and open terms would be new *capabilities*.
- **One state per silent SCC cannot be proved inside a coinduction**
  (*limit*; counterexample pinned as `CircularTransfer`). Very large
  systems (`Proc/Test4`, 9720 states) are therefore *decided* on demand
  but not *proved* directly. `Test4` is proved through an explicit
  structural congruence instead (`doc/structural-congruence.md`). That is
  why `Test4` has no `PluginProofs.v`.
- **Divergence.** `weak_sim` and `weak_bisimilar` ignore divergence, as
  their definitions do. Divergence-sensitive notions (as in `rocq-sims`)
  are out of scope (`future-work.md`, "Set aside") unless @dcastrop
  wants them.

**Cost**
- **Proofs cost far more than deciding.** At width n = 3 (162 states a
  side), `Bisimilarity.fsm` takes 19ms and the proof 7 minutes (55k
  steps, 4.0GB). CADP `Size2` glued ≈ layered is decided in ~45s and
  ~1.5GB, but its proof runs out of memory at 10GB, and still at 24GiB on a
  31GB host (2026-10-15/16; `measurements/cadp-large.md`).
  `decide-vs-prove.md` has the full comparison.
- **`Auto` goes nested on an FSM saturated on demand** unless `MeBi
  Config Bounds Game` is set, because estimating would walk the whole
  game. It says so in a notice. For a `weak_bisimilar` goal the nested
  path is the one that does not finish on the checked-in proofs. At CADP
  `Size2` the estimate (~1 min) put nested at over 10.3M goals, against
  514,020 pairs and 2.06M moves mutual. Setting the bound by hand avoids
  it. Whether `Auto` should estimate by default there is an open
  *optimization* question. On the 31GB host, under `Answers Auto`, the
  estimate took 4,489s (not ~1 min) and found a game of 78,202 pairs and
  312,808 moves, and the mutual proof still ran out of memory at 24GiB after
  16h in all. Under `Answers Default` the earlier figures come back (`Begin`
  82s, 514,020 pairs, memory ~2.2GiB for 16h, 5.0GiB at 24h) and the proof
  was still unfinished when stopped at 24h. So the answer policy changes this
  proof's game and cost a great deal, and `Auto`'s plan was the costlier to
  run in memory; why is unknown (`measurements/cadp-large.md`).
- **Heavy proofs need a memory cap**, one per process. The ABP and
  `Test4` proofs peak at ~3.8-4.3GB; two such proofs in one file were
  OOM-killed at 6GB. `MeBi Config Bounds Memory <mb>` (2026-10-16; on by
  default at 75% of RAM, or 90% of a cgroup cap) stops a command with an
  error before that, but softly: one solver step can
  overshoot it, `Qed` is not checked at all, and it bounds one process, so
  a parallel build (`make -j`) is not covered. Keep the OS cap
  (`systemd-run ... -p MemoryMax=...`) as the backstop.
- **Deep derivations make `Qed` dominate.** At 64 layers, `Qed` takes
  71s against 7s of solving, and `Qed` grows ~13× per doubling of the
  layers.

**Output**
- **`MeBi Draw` draws a label as a node of the layout, which costs layout
  time** (*limit*; found 2026-11-01, label nodes added 2026-11-02; not
  pinned: the compile tests do not look at the picture). A label drawn as
  TikZ places a quoted label sits beside the last stretch of its arrow (its
  `pos` is measured along that stretch only, and the layered layout routes
  an arrow as several; no style moves it), so labels cover each other where
  arrows meet or are taken for another arrow's. Each label is therefore a
  node of the layout, which keeps room for it, at 2.2 times the layout time at
  31 states and 4.1 times at 100, where it takes 85 s against the 60 s limit
  (`doc/measurements/draw-layout-time.md`); `MeBi Config Draw Labels Beside`
  gives the cheaper, older placement back. The layered layout keeps its
  layers a fixed distance apart from centre to centre, so when growing right
  a narrow label (the silent step's tau) leaves a longer visible line than a
  wide one, and the arrows are polylines (rounded at their corners), so an
  arrow back growing down is an S-curve: both are the router's and the
  layout's, and Graphviz's measure from the borders and draw splines
  (`doc/future-work.md`). The label of an arrow back to a
  state it follows is half way along the longest path the arrow closes, not
  always half way along the arrow: the layout may stretch the arrow beyond
  that path, when the label sits nearer one end. Ways out, and the Graphviz
  engine that would route first and label second, are in
  `doc/future-work.md`, "`MeBi Draw`".
- **`MeBi Config Draw Engine Graphviz` is opt-in and needs `dot` on the `PATH`
  for a PDF or a PNG** (*limit*, by design; found 2026-11-02; the file-writing
  and the missing, failing and slow `dot` are pinned by `test/tests.ml`, the
  drawing by it only where `dot` is installed). Without `dot` it warns and keeps
  the `.dot`. Its text is in Graphviz's font and not the document's, a label
  cannot hold LaTeX, the picture cannot be restyled from a document, `Style`,
  `Layout` and `TwoWay` do not apply to it, and its spacing and font are fixed.
  Only Graphviz 15.1.1 was tried; layouts differ between versions.
  A silent step's tau is the mathematical bold italic small tau (U+1D749) in
  Latin Modern Math, then STIX Two Math and Asana Math; where none is installed
  Graphviz takes the letter from whatever font has it, so the glyph differs.
- **`MeBi Draw` starts its programs (`lualatex`, `pdftocairo`, `gs`, `dot`)
  through a POSIX `sh`** (*limit*; found 2026-11-02; the message is pinned by
  `test/tests.ml`). On a system without one (native Windows, say) each is
  reported as not started, with a warning that names `sh`, and the files made
  so far are kept; never an error. The notifier starts `notify-send` itself,
  with no `sh`.
- **Under vsrocq, the `origin:` line comes from the saved file, so an unsaved
  edit makes it `(line unknown)`** (*limit*, by design; not pinned: it needs
  vsrocq, which `test/rocq/Test.v` does not run). vsrocq parses with no source
  file, and its `Loc.line_nb` is short, by 3 lines in one probe and by 54 in
  the author's example, so it cannot be printed. Its character offsets
  (`Loc.bp`, `bol_pos`) are exact, so `Rocq_output.origin_location` counts the
  newlines before `bp` in the document's file, found through the load path from
  its logical path (`Lib.library_dp ()`), and prints `Logical.path, line N`.
  vsrocq checks the editor's buffer, not that file, so the text at `bp` must
  mention `MeBi`; if the file is missing or an unsaved edit moved the command,
  the header says `Logical.path (line unknown)` rather than a wrong line. In
  `rocq compile` the line is the file's; in `rocq repl` (path `Top`) it is
  `Loc.line_nb`, which is right there. Dump names use the logical path alone.
- **`Output Wrap Flow` follows the window in vsrocq's proof panel, but can
  overflow it by about a character** (*limit*, in vsrocq's display, not the
  plugin; found 2026-11-01). `Flow` wraps at Rocq's printing width in `rocq
  compile` and `rocq repl` (78, or `Set Printing Width`). Through `vsrocqtop`
  over LSP a `Notice` or `Warning` arrives as text wrapped at 78 (vsrocq renders
  those with `Pp.string_of_ppcmds` and has no width setting of its own). An
  `Info`, which includes `Result`, goes to the proof panel as boxes, and there
  the author sees it laid out correctly. The panel's `pp-display` (vsrocq 2.5.0,
  `pp-display/dist/pp-display.js`) re-flows to the pane's width in pixels, with
  a `ResizeObserver` and a canvas `measureText`, breaking when the line so far
  plus the next word is wider than the pane. **The author sees it overflow by a
  character or so.** A likely cause, from reading that code and *not seen*: it
  ignores a resize of 10 pixels or less (`Math.abs(width change) <= 10`), which
  is about a vertical scrollbar, so a message long enough to make one appear
  after the layout is left that much too wide. Nothing in the plugin can move
  that margin, and padding the words would show as extra spaces. `Wide`, `Slim`
  and `Width <n>` fill to a fixed width here and hold in any client, but do not
  follow the window; set one a column or two under the visible width if the
  overflow matters.
- **Wrapping reads the text, not the display** (*limit*, by design). A line
  with a run of two spaces or a tab is taken for aligned columns and kept, so
  a prose line that has a double space in it is not wrapped. A line starting
  with a brace, a square bracket or a double quote is taken for JSON and
  kept, as is a divider (only dashes, equals signs, underscores, asterisks and
  spaces). Width counts characters, so a wide glyph counts as one. Every kind of
  message the plugin prints is wrapped alike, `Debug` and `Trace` included, and
  so are `MeBi Help`, `Message`, `Debug`, `Divider` and the errors the plugin
  raises (from 2026-11-01; until then those went round the wrapping, found
  when `MeBi Help Premises` still overflowed). **Not wrapped:** Rocq's own
  errors and warnings, and the short `MeBi: ...` messages raised inside
  tactics (`lib/rocq_tools/premise_search.ml`), which cannot reach
  `Rocq_output`.
