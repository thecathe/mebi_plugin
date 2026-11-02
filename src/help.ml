(** [MeBi Help] (backlog item F). Topics are paths, e.g.
    [["Config"; "Bounds"; "Saturation"]] for [MeBi Help Config Bounds Saturation]. The figures quoted are computed from the same constants the
    plugin's errors and notices use ({!Api.bytes_per_weak_action},
    {!Api.mb_per_extracted_state}, {!Api.default_saturation_bound}), so the
    help cannot drift from what the plugin actually reports. *)

(* See the [.mli]. *)
let topics : string list list =
  [ [ "Run" ]
  ; [ "Draw" ]
  ; [ "Sim" ]
  ; [ "Benchmark" ]
  ; [ "Premises" ]
  ; [ "Config" ]
  ; [ "Config"; "Bounds" ]
  ; [ "Config"; "Bounds"; "Saturation" ]
  ; [ "Config"; "Saturation" ]
  ; [ "Config"; "Weak" ]
  ; [ "Config"; "FailIf" ]
  ; [ "Config"; "Solver" ]
  ; [ "Config"; "Output" ]
  ; [ "Config"; "Draw" ]
  ; [ "Config"; "Notify" ]
  ]
;;

(** [name p] is the command that shows the topic [p]. Raises nothing. *)
let name (path : string list) : string = String.concat " " ("MeBi Help" :: path)

(** [overview ()] is the help overview: what MeBi does and every topic.
    Raises nothing. *)
let overview () : string =
  String.concat
    "\n"
    ([ "MeBi: build the LTS of a Rocq term from an inductive relation, check \
        (weak) bisimilarity, and search for weak_sim and weak_bisimilar \
        proofs."
     ; ""
     ; "Help topics:"
     ]
     @ List.map (fun p -> "  " ^ name p ^ ".") topics
     @ [ ""; "See also README.md." ])
;;

(** [saturation_table ()] is the memory saturation needs at a few bounds,
    from {!Api.bytes_per_weak_action}, the default marked. Raises nothing. *)
let saturation_table () : string =
  let lo, hi = Api.bytes_per_weak_action in
  (* [row n] is the table's line for a bound of [n] weak actions. *)
  let row (n : int) : string =
    Printf.sprintf
      "  %12i weak actions   %s - %s%s"
      n
      (Api.human_bytes (n * lo))
      (Api.human_bytes (n * hi))
      (if Int.equal n Api.default_saturation_bound then "   (default)" else "")
  in
  String.concat
    "\n"
    (List.map row [ 1_000_000; 5_000_000; 10_000_000; 20_000_000 ])
;;

(* See the [.mli]. *)
let text : string list -> string option = function
  | [] -> Some (overview ())
  | [ "Run" ] ->
    Some
      "MeBi Run LTS <term> Using <lts> [<lts>...].\n\
       MeBi Run FSM | Saturate | Minimize <term> Using <lts> [<lts>...].\n\
       MeBi Run Bisim <term> With <lts> And <term> With <lts> Using <lts>...\n\
       MeBi Run Merge <term> With <lts> And <term> With <lts> Using <lts>...\n\
       MeBi Run Bisim <term> With <lts> And <term> With <lts> As <name> [Using \
       <lts>...]\n\
       MeBi Run Sim <term> With <lts> And <term> With <lts> [As <name>] [Using \
       <lts>...]\n\n\
       Build the LTS reachable from <term>, then optionally saturate it (weak \
       transitions across silent steps), minimize it, or check two for (weak) \
       bisimilarity. The first relation after Using is the one <term> steps \
       by; the rest are the relations its constructors' premises mention \
       (layered LTSs). With As <name>, Run Bisim also states weak_bisimilar as \
       the Example <name>, opens its proof and begins the proof search, as \
       MeBi Sim Begin would: continue with MeBi Sim Solve <n>, then Qed. \
       Nothing opens if the two are not bisimilar. Run Sim asks whether the \
       first term is weakly simulated by the second (a preorder, so the order \
       matters); with As <name> it states weak_sim and opens its proof the \
       same way. It walks the pairs of states reachable from the two terms; \
       when an FSM is saturated on demand that walk needs MeBi Config Bounds \
       Game <n>. See: MeBi Help Premises, MeBi Help Sim."
  | [ "Sim" ] ->
    Some
      "MeBi Sim Begin <lts> <term> And <lts> <term> Using <lts>...\n\
       MeBi Sim Step.  MeBi Sim Solve <n>.\n\n\
       Inside a proof of [weak_sim lts1 lts2 t1 t2] (one direction) or \
       [weak_bisimilar lts1 lts2 t1 t2] (weak bisimilarity, both directions in \
       one proof): Begin computes both LTSs and their bisimilarity, then \
       Step/Solve run the proof search. Solve n permits n + 1 steps and stops \
       as soon as the proof closes. If it runs out it says which cofix \
       strategy was used; see MeBi Help Config Solver. For weak_bisimilar, \
       Auto usually picks the mutual cofix; if a proof does not close, try the \
       other strategy. For weak_sim, the two states need only be similar: if \
       they are not bisimilar, Begin checks the weak simulation preorder \
       instead and refuses only if they are not similar."
  | [ "Benchmark" ] ->
    Some
      "MeBi Benchmark LTS <min> <max> <term> Using <lts> [<lts>...].\n\n\
       Times repeated LTS construction over a range of sizes."
  | [ "Premises" ] ->
    Some
      (Printf.sprintf
         "Which constructor shapes are supported. An LTS is an inductive \
          relation [term -> label -> term -> Prop]. For each constructor, the \
          source term is matched, then its premises are handled:\n\
         \  - premises over an LTS given in Using (the same one, or another: \
          layered LTSs) are explored; several are allowed;\n\
         \  - any other premise is decided once it is closed (immediately, or \
          after the LTS premises fix what it mentions): an equation by \
          comparing its sides, any other inductive proposition (<=, <, In, \
          Forall, /\\, \\/, ...) by a proof search over its constructors, at \
          most %i deep (MeBi Config Premise Depth <n>). A false premise drops \
          the transition; in a proof, a true one is closed with the proof \
          found, and a false one in a hypothesis is refuted. A binder only \
          such premises mention ([In q l -> P q -> ...], no LTS step on [q]) \
          is chosen in the proof by solving those premises together;\n\
         \  - a premise that computes something -- the target, or what an LTS \
          premise needs ([In q l -> lts q a q']) -- is enumerated, each \
          solution a transition of its own; MeBi warns if the solutions may be \
          incomplete. An LTS premise whose source nothing determines ([lts q a \
          q'] with [q] free) is enumerated the same way, and each source found \
          explored;\n\
         \  - a transition with a binder nothing determines ([lts (S n) a n], \
          [n] free) may stand for infinitely many: it is left out, with a \
          warning, so the LTS may be missing transitions;\n\
         \  - an LTS with any such warning is incomplete: an error, as when \
          exploration hits the bound, unless [MeBi Config FailIf Incomplete \
          False];\n\
         \  - a negation [~ P] holds iff P is refuted by a complete search, \
          and is proved by refuting P;\n\
         \  - a bounded universal over nat, [forall k, k < n -> P k] or [k <= \
          n] (also [n > k]), [n] a number once the premise is closed, holds \
          iff every [P i] does: each is decided as above, and the proof is \
          assembled from theirs with the lemmas in MEBI.Premises; a false one \
          is refuted at a false [P i]. Only up to %i values of [k] (MeBi \
          Config Premise Range <n>): each costs a search, and the proof grows \
          with the square of the range; a wider one is left undecided, with a \
          warning saying so;\n\
         \  - with [MeBi Config Premise Tactic <tactic>], a premise the search \
          leaves undecided is tried with that tactic (proving it, or its \
          negation);\n\
         \  - anything else cannot be decided -- opaque functions or axioms, a \
          search cut off by the depth: the constructor is applied as if the \
          premise held, with a warning, so the LTS may contain transitions \
          that do not exist. A Run Bisim verdict on it may be wrong; a proof \
          cannot be, since Qed checks the premise."
         !Premise_search.max_depth
         !Premise_search.max_range)
  | [ "Config" ] ->
    Some
      "MeBi Config Reset [Bounds | Weak | FailIf | Output | Draw | Notify].\n\n\
       Settings, each with its own topic:\n\
      \  MeBi Help Config Bounds.     how big an LTS (and its saturation) may \
       get\n\
      \  MeBi Help Config Saturation. saturating whole, or on demand\n\
      \  MeBi Help Config Weak.       which label is silent (weak bisimilarity)\n\
      \  MeBi Help Config FailIf.     which outcomes are errors, not warnings\n\
      \  MeBi Help Config Solver.     the proof search's cofix strategy\n\
      \  MeBi Help Config Output.     which messages are shown, how they wrap, \
       and the results' format (plain text by default)\n\
      \  MeBi Help Config Draw.       what MeBi Draw makes, how big, and how \
       it looks\n\
      \  MeBi Help Config Notify.     a desktop notification when a long \
       command ends"
  | [ "Config"; "Bounds" ] ->
    let lo, hi = Api.mb_per_extracted_state in
    Some
      (Printf.sprintf
         "MeBi Config Bounds As Num States <n>.\n\
          MeBi Config Bounds As Num Transitions <n>.\n\
          MeBi Config Bounds Saturation <n>.\n\
          MeBi Config Bounds Game <n>.\n\
          MeBi Config Bounds Memory <mb>.\n\
          MeBi Config Bounds Draw States <n> | Transitions <n> | Time <s>.\n\
          MeBi Config Premise Depth <n>.\n\
          MeBi Config Premise Range <n>.\n\
          MeBi Config Reset Bounds.\n\n\
          Exploration stops after <n> states (default %s) or transitions; an \
          LTS cut short is an error unless [MeBi Config FailIf Incomplete \
          False]. Extraction has measured %.2f-%.2fMB per state on top of a \
          fixed 0.1-0.3GB, so a state bound past ~%i prints a memory notice. \
          Logging the result (Output \"Result\" / \"DecodeResults\" / \
          \"DumpResults\") costs far more, ~0.65MB per state. For the \
          saturation bound see MeBi Help Config Bounds Saturation; for the \
          premise search depth and range, MeBi Help Premises; for how large a \
          diagram MeBi Draw will draw, MeBi Help Config Draw.\n\n\
          Bounds Memory stops a command, with an error, once the whole Rocq \
          process uses more than <mb> megabytes (its resident memory and swap \
          on Linux). Now: %s. The default is 75%% of the machine's RAM, or \
          90%% of a cgroup memory cap the process runs under (systemd-run -p \
          MemoryMax=...) if that is smaller; there is none where neither can \
          be read. 0 turns it off. It is checked during extraction, \
          saturation, the up-front game walks and estimates, and between Solve \
          steps, so one step can overshoot it, and Qed is not checked at all: \
          keep an OS-level cap as a backstop. It bounds this one process, so \
          parallel builds (make -j) need an OS cap each. Over the bound, the \
          heap is compacted, returning free memory to the system, before the \
          command is stopped. Reset Bounds restores the default."
         (match Api.default_bounds with
          | Api.States n -> Printf.sprintf "%i states" n
          | Api.Transitions n -> Printf.sprintf "%i transitions" n)
         lo
         hi
         (int_of_float (1000. /. hi))
         (Memory_guard.describe ()))
  | [ "Config"; "Bounds"; "Saturation" ] ->
    let lo, hi = Api.bytes_per_weak_action in
    Some
      (Printf.sprintf
         "MeBi Config Bounds Saturation <n>.   (default %i)\n\n\
          The most weak actions saturation may produce. Saturation (used by \
          Run Saturate, Minimize, Bisim and Sim Begin when a label is silent) \
          can be orders of magnitude larger than the LTS: one weak action per \
          (state, label, state reachable by tau* label tau*). Before \
          saturating, MeBi computes that number exactly and cheaply. Above the \
          bound, Run Bisim and Sim Begin saturate on demand instead, with a \
          warning (MeBi Help Config Saturation), holding at most <n> weak \
          actions; Run Saturate and Minimize refuse with Saturation_Too_Large \
          (or warn, with MeBi Config FailIf Oversaturated False). Run [MeBi \
          Config Output \"Info\" True.] to see each estimate.\n\n\
          Measured memory is %i-%i bytes per weak action (the higher for \
          larger LTSs: each keeps its shortest witness path). Choose a bound \
          your machine can hold:\n\
          %s\n\n\
          Time grows faster than the count: a partial Proc/Test4 LTS with 400k \
          weak actions takes ~13s. Proc/Test4 itself (9720 states) would \
          saturate to 74.6M."
         Api.default_saturation_bound
         lo
         hi
         (saturation_table ()))
  | [ "Config"; "Saturation" ] ->
    Some
      "MeBi Config Saturation OnDemand True | False | Auto.   (default Auto)\n\
       MeBi Config Reset Bounds.   (restores Auto)\n\n\
       How Run Bisim and Sim Begin saturate each FSM. Whole: every weak action \
       up front, which for an LTS with large silent cycles can take far more \
       memory than the machine has (Proc/Test4: 74.6M weak actions, 34-67GB). \
       On demand: each state when the check or the proof needs it, from the \
       same code, so with the same weak actions and witnesses, holding at most \
       Bounds Saturation of them (the oldest dropped and saturated again if \
       needed); bisimilarity is decided on the quotient by silent strongly \
       connected components instead (states in one silent SCC have the same \
       weak moves; Proc/Test4's 9720 states make 81), with the same verdict. A \
       proof is the same proof, step for step; it may take longer, as dropped \
       states are saturated again.\n\n\
       Auto saturates on demand exactly the FSMs whose saturation would exceed \
       Bounds Saturation, and warns when it does; True does so for every FSM; \
       False refuses those FSMs (Saturation_Too_Large), or with FailIf \
       Oversaturated False saturates them whole anyway. Run Saturate and \
       Minimize always saturate whole.\n\n\
       On demand, planning the whole proof up front walks every pair the proof \
       can reach, saturating as it goes. So Solver MutualCofix True, Answers \
       Greedy and Answers Minimal are refused unless MeBi Config Bounds Game \
       <n> is set (unset by default); with it, the walk runs within <n> pairs \
       and past it they are refused. The two Autos estimate or plan within the \
       bound, and otherwise (or past it) take the nested cofix and answer move \
       by move."
  | [ "Config"; "Weak" ] ->
    Some
      "MeBi Config Weak As Option <type>.\n\
       MeBi Config Weak As <term> Of <type>.\n\
       MeBi Config Weak1 / Weak2 ...   (one side of Bisim/Merge/Sim only)\n\
       MeBi Config Reset Weak.\n\n\
       Mark the silent label: [As Option T] makes [None] silent in an [option \
       T]-labelled LTS; [As c Of T] makes constructor c of T silent. With a \
       silent label set, bisimilarity is weak and FSMs are saturated first."
  | [ "Config"; "FailIf" ] ->
    Some
      "MeBi Config FailIf Empty | Incomplete | NotBisimilar | Oversaturated \
       True | False.\n\
       MeBi Config Reset FailIf.\n\n\
       Whether an empty LTS (default False), an incomplete one (True), a \
       negative bisimilarity result (True), or a saturation above Bounds \
       Saturation (True) is an error rather than a warning. An LTS is \
       incomplete if exploration was cut short by the bound, or if it is only \
       an approximation: a premise MeBi could not decide (it may contain \
       transitions that do not exist), or a premise search or transition it \
       could not complete (it may be missing some). See MeBi Help Premises."
  | [ "Config"; "Solver" ] ->
    Some
      "MeBi Config Solver MutualCofix True | False | Auto.\n\n\
       How the proof search introduces coinduction hypotheses: False mints a \
       nested cofix per new pair; True opens the proof with one mutual cofix \
       over every pair it will reach; Auto (default) measures both on the \
       model before the proof starts and picks, announcing it when it takes \
       the mutual path.\n\n\
       MeBi Config Solver Answers Default | Greedy | Minimal | Auto.\n\n\
       How the proof search chooses each answer. Every step of a weak_sim or \
       weak_bisimilar proof has one system make a move (x -a-> x') and the \
       other answer it with a weak move to some y' such that (x', y') can be \
       proved related in turn. Usually several answers would do; which one is \
       taken decides the proof's next goals, and so its length.\n\n\
       Default -- the policy the solver used until 2026-10-15 -- chooses each \
       answer on its own, with no look-ahead: stand still if the move was \
       silent and the answering state is already bisimilar to x'; otherwise \
       take the weak transition with the shortest witness (fewest steps to \
       justify) into the bisimilarity class of x', ending at its \
       lowest-numbered state (the one extraction discovered first). For a \
       weak_sim goal between states that are similar but not bisimilar, the \
       same two tries against the states that simulate x'. Because no choice \
       takes the others into account, a proof can visit many more pairs than \
       it needs -- weak_bisimilar proofs especially, whose two directions each \
       pick answers the other never uses.\n\n\
       Greedy, Minimal and Auto plan every answer at Begin, before the first \
       step, and Begin announces the plan and its predicted cost. Greedy \
       prefers an answer whose pair has already been reached. Minimal answers \
       within a relation that no pair can be removed from. Auto plans all \
       three and keeps the cheapest predicted. Auto is the default; on an FSM \
       saturated on demand it answers move by move, as Default does, unless \
       Bounds Game is set. Measured on the checked-in examples (2026-10-02), \
       Auto was never slower than Default and cut weak_sim proofs by 17% and \
       weak_bisimilar proofs by 60%; Minimal alone was slower on many weak_sim \
       proofs. Every answer is still checked by Qed, so a policy can only \
       change how long a proof is, never whether it is correct."
  | [ "Config"; "Output" ] ->
    Some
      "MeBi Config Output \"<Kind>\" True | False.\n\
       MeBi Config Output Format Text | JSON.\n\
       MeBi Config Output Wrap Off | Flow | Wide | Slim.\n\
       MeBi Config Output Wrap Width <n>.\n\
       MeBi Config Output Width Wide <n>.\n\
       MeBi Config Output Width Slim <n>.\n\
       MeBi Config Reset Output.\n\n\
       Results (the FSMs, LTSs and verdicts shown with Output \"Result\" True, \
       and dumps) are plain text by default: the states and labels numbered \
       with their terms, then the moves as from -label-> to, under a header \
       saying where they came from: file and line (in an editor, the \
       document's logical path and its line), command, terms, and the \
       relations with their constructors. Format JSON prints them as JSON \
       instead, with the header as \"origin\". Output \"Detail\" adds each \
       move's derivation tree (in JSON, the constructors' bindings and the \
       annotations of weak actions too); it is off for plain text and on for \
       JSON unless set, and once set holds for both. Reset Output restores \
       plain text, detail as the format has it, and wrapping off.\n\n\
       Wrapping fits a message to a width. A paragraph of prose is broken \
       between words and the continuation indented; rows of aligned columns \
       (the states, labels and moves of a result) and JSON are never cut. Off \
       (the default) leaves a message as one block. Flow breaks it where \
       whatever shows it says: Rocq prints text at its printing width (78, or \
       Set Printing Width), and a client that lays out the boxes itself can \
       follow its own window. vsrocq shows a Notice or Warning as text at 78, \
       and sends an Info to its proof panel as boxes. Width <n> breaks at <n> \
       columns here, so it holds in every client but does not follow the \
       window. Wide and Slim are two named widths, 120 and 60 until set with \
       Output Width Wide <n> or Output Width Slim <n> (at least 20); setting \
       one changes the wrapping at once if it is the one chosen, and does not \
       choose it. Wrap Wide or Wrap Slim chooses. It covers everything the \
       plugin prints, MeBi Help and the errors it raises included, but not \
       Rocq's own messages.\n\n\
       Toggle one message kind: Debug, Info, Notice, Warning, Error, Trace, \
       Result, Show, DecodeResults, DumpResults, Detail. Info, Notice, \
       Warning, Error and Show are on by default; Debug, Trace and Result are \
       off. Info is the routine kind: MeBi Config Output \"Info\" False hides \
       it and keeps the rest. DumpResults (off by default) writes each FSM and \
       result, in the format set, into ./_dumps/, for debugging: on a large \
       FSM that is hundreds of MB and many seconds a command."
  | [ "Draw" ] ->
    Some
      "MeBi Draw LTS <term> Using <lts> [As \"<name>\"] [<lts>...].\n\
       MeBi Draw FSM <term> Using <lts> [As \"<name>\"] [<lts>...].\n\n\
       Draw the LTS (or FSM) of <term> as a TikZ picture, laid out by LuaTeX's \
       graphdrawing library (a layered layout), into the directory set by MeBi \
       Config Draw Dir (./_diagrams/ by default), as three files: <name>.tikz, \
       the picture, to \\input into a LuaLaTeX document; <name>.style.tikz, \
       its styles; and <name>.tex, a document that draws the two. With MeBi \
       Config Draw Format PDF (the default) it also runs lualatex to make \
       <name>.pdf, and with PNG a PNG of that, by pdftocairo or gs. A program \
       that is missing, fails, or runs past the time limit is warned about, \
       and the files made so far are kept.\n\n\
       <name> is the one given by As (letters, digits, - _ and . only), else \
       one made from the term, such as lts-old; files of that name are \
       replaced. States are numbered as in the plain-text dump of the same \
       system. A state and a label are drawn without the parentheses round all \
       of them, and the labels without Some if every label that is not silent \
       has it (so a bare None, with no silent label configured, keeps them \
       all). A silent label is drawn as tau (see MeBi Help Config Weak), the \
       two arrows between a pair of states in opposite directions are bent \
       apart, and an LTS that is incomplete says so under the picture.\n\n\
       A system over the draw bound is refused: the layout's time grows \
       quickly with its size. For the bound, the formats and the look of each \
       part of the picture, see MeBi Help Config Draw."
  | [ "Config"; "Draw" ] ->
    let c : Api.draw_config = Api.draw_config_default () in
    Some
      (Printf.sprintf
         "MeBi Config Draw Format TeX | PDF | PNG.\n\
          MeBi Config Draw Dir \"<dir>\".\n\
          MeBi Config Draw Style \"<Component>\" \"<TikZ options>\".\n\
          MeBi Config Bounds Draw States <n>.\n\
          MeBi Config Bounds Draw Transitions <n>.\n\
          MeBi Config Bounds Draw Time <s>.\n\
          MeBi Config Reset Draw.\n\n\
          How MeBi Draw draws (MeBi Help Draw). Defaults: %s.\n\n\
          Bounds: a system with more states (or, if set, transitions) than the \
          bound is refused, and, as with Bounds As Num, the last of States and \
          Transitions set is the one in force. LuaTeX's layout took about 3 \
          seconds at 50 states, 21 at 100 and 88 at 150 (one synthetic graph \
          of each size, about 1.4 transitions a state; it is time that limits \
          it, not memory: doc/measurements/draw-layout-time.md). Time is how \
          long each program (lualatex, then pdftocairo or gs) may run before \
          it is killed, %i seconds by default. Reset Bounds restores the \
          bounds and the time limit; Reset Draw restores everything here.\n\n\
          Style: the picture names a TikZ style for each part and defines \
          none; <name>.style.tikz defines them, from a default for each \
          component and then your options, which come after and so win. An \
          empty string restores a component's default. Initial and Terminal \
          build on State, SilentEdge on Edge, and SilentLabel on Label. Layout \
          is what \\graph gets, so it is the place for spacing. For example:\n\
         \  MeBi Config Draw Style \"State\" \"fill=yellow!20\".\n\
         \  MeBi Config Draw Style \"Edge\" \"draw=blue\".\n\
         \  MeBi Config Draw Style \"Label\" \"draw=gray!50, rounded \
          corners=1pt\".\n\
          (the last frames each label). A label sits beside the last stretch \
          of its arrow, not on its middle: TikZ places it along that stretch \
          only, and the layered layout makes an arrow of several.\n\
          The defaults:\n\
          %s\n\n\
          To style a picture by hand, leave <name>.style.tikz out and define \
          the same names in your own document (Layout's under graphs/, as \
          graphs/mebi layout/.style=...). The libraries and LuaLaTeX it needs \
          are listed at the top of the style file."
         (Printf.sprintf
            "format %s, directory %s, at most %s"
            (Draw_output.format_name c.draw_format)
            c.draw_dir
            (match c.draw_bounds with
             | Api.States n -> Printf.sprintf "%i states" n
             | Api.Transitions n -> Printf.sprintf "%i transitions" n))
         Api.default_draw_time
         (String.concat
            "\n"
            (List.map
               (fun comp ->
                 Printf.sprintf
                   "  %-12s %s"
                   (Draw_style.name comp)
                   (Draw_style.default comp))
               Draw_style.components)))
  | [ "Config"; "Notify" ] ->
    Some
      (Printf.sprintf
         "MeBi Config Notify After <seconds>.\n\
          MeBi Config Notify Off.\n\
          MeBi Config Notify Test.\n\
          MeBi Config Reset Notify.\n\n\
          A desktop notification when a long command ends, so a long run can \
          be left going. Off by default (now: %s). After <seconds> turns it \
          on: a MeBi Run, Draw or Benchmark command, or a MeBi Sim command \
          (Solve, Step, Begin), that takes that long or longer ends with a \
          notification naming it and how long it took, whether it succeeded or \
          ended with an error, and a line in the output saying the same. Both \
          give the most memory the process reached against the memory bound \
          (MeBi Config Bounds Memory), and what it held when the command \
          began: Peak memory 3.1 GB of the 11.7 GB bound (26%%), up from 2.4 \
          GB at its start. That is the process's, not the command's own: \
          memory earlier commands left counts, which is why the start is \
          given. A command the memory bound stopped says so, and where, \
          instead of reporting an error. A shorter command prints and sends \
          nothing. After 0 announces every command. A command run from inside \
          another does not announce itself.\n\n\
          It runs notify-send (the libnotify package) and needs a notification \
          server in the desktop session; MeBi needs neither. Where notify-send \
          is not on PATH, or nothing receives the message, the command \
          finishes as it would have, with one warning saying why. Test sends \
          one now, whatever the setting, and says whether it went: use it \
          before a demonstration. Off, and Reset Notify, turn it off."
         (match Notify.threshold () with
          | None -> "off"
          | Some s -> Printf.sprintf "on, after %i seconds" s))
  | _ -> None
;;

(* See the [.mli]. *)
let show (path : string list) : unit =
  match text path with
  | Some t -> Feedback.msg_notice (Rocq_output.render_text t)
  | None ->
    Feedback.msg_notice
      (Rocq_output.render_text
         (Printf.sprintf
            "No help for [%s]. %s"
            (String.concat " " path)
            (overview ())))
;;
