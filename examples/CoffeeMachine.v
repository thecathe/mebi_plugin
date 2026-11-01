(** * A coffee machine, its upgrade and its replicas

    The running example of the MeBi talk.

    1. [Classic]: coins in, a drink out, change back.
    2. [Upgrade]: more drinks and a card reader. It should do everything
       the classic machine does.
    3. [Replica]: the classic machine, built differently inside. It should
       behave the same.
    4. The worn replica: a replica that can silently run out of coffee beans.
       It should look the same too, but it is not quite the same. It is only
       a sketch, at the end.

    What the machines share (coins, drinks and labels) comes first. Then each
    machine is a module of its own, written out in full, with its own states
    and rules, and with the proofs that compare it to the classic machine. *)

Require Import MEBI.loader.
Require Import MEBI.Bisimilarity.
From Stdlib Require Import List Arith.
Import ListNotations.


(** ** Shared: coins, drinks and labels *)

(** *** Coins, drinks and prices

    Money is counted in pence. Coins, prices and credit are all multiples of
    10p, so change can always be made with the coins we have.

    [drink] already holds the drinks of the upgrade. The classic machine just
    never offers [latte] or [espresso]: which drinks a machine offers is its
    own [drinks] list, below. *)

Inductive coin : Set := ten | twenty.

Inductive drink : Set := tea | coffee | latte | espresso.

Definition value (c : coin) : nat :=
  match c with ten => 10 | twenty => 20 end.

Definition price (d : drink) : nat :=
  match d with tea => 10 | coffee => 20 | latte => 30 | espresso => 50 end.

(** The coins the machines accept, as a list. The rules below use it to say
    which coin a rule is about. *)

Definition coins : list coin := [ten; twenty].

(** The coin handed back when [n] pence is owed: the largest that fits, and
    none when nothing is owed. It is a list so that it can be used as a
    premise below, as [In c (change n)]. *)

Definition change (n : nat) : list coin :=
  if Nat.leb 20 n then [twenty]
  else if Nat.leb 10 n then [ten]
  else [].


(** *** Labels: what a person at the machine can see

    The user puts coins in ([Insert]), asks for a drink ([Ask]) or cancels
    ([Cancel]). The machine hands over a drink ([Serve]) and hands back coins
    ([Return]), whether that is a refund or change. [Tap] is only for the
    upgrade's card reader. Everything else the machine does is silent.

    The labels are shared for the same reason as the drinks: [weak_sim] and
    [weak_bisimilar] relate two machines over one type of labels, so a label
    type of each machine's own could not be compared with another's. Each
    machine's rules just use the labels it has. *)

Inductive label : Set :=
| Insert : coin -> label
| Ask    : drink -> label
| Cancel : label
| Serve  : drink -> label
| Return : coin -> label
| Tap    : label.

(* ANCHOR: weak-config/deciding *)
MeBi Config Weak As τ Of label.
(* ANCHOR_END: weak-config/deciding *)

(** A silent step (a tau) is [None]. The proofs need this form: [weak_sim] and
    [weak_bisimilar] are stated over [option label]. (A [tau] constructor in
    [label] would do for [MeBi Run Bisim], which only decides, but not for
    them.) *)

(* ANCHOR: config-weak *)
MeBi Config Weak As Option label.
(* ANCHOR_END: config-weak *)


(** ** 1. The classic machine *)

Module Classic.

  (** The drinks this machine offers. *)

  Definition drinks : list drink := [tea; coffee].

  (** *** States

      A state is what the machine is doing, and how much money it holds for the
      customer (its credit). Only the sum matters, not the order the coins went
      in, so the credit is a single number.

      - [Idle]: waiting for coins and a request.
      - [Brewing d]: [d] was asked for, and is being made (silently).
      - [Ready d]: [d] is ready to be served.
      - [Giving]: handing back what is left of the credit, a coin at a time. *)

  Inductive mode : Set :=
  | Idle
  | Brewing (d : drink)
  | Ready   (d : drink)
  | Giving.

  Definition term : Set := mode * nat.

  Definition cap : nat := 30.

  (** *** Semantics

      The credit put in with coins is capped at [cap]. The [In ...] premises
      matter: nothing else says which [c] or [d] a rule is about, and the
      plugin cannot guess. *)

  Inductive lts : term -> option label -> term -> Prop :=
  (* insert coins up to the cap *)
  | insert c n : In c coins -> Nat.leb (n + value c) cap = true ->
      lts (Idle, n) (Some (Insert c)) (Idle, n + value c)
  (* ask for drink: price taken from credit (must have enough) *)
  | ask d n : In d drinks -> Nat.leb (price d) n = true ->
      lts (Idle, n) (Some (Ask d)) (Brewing d, n - price d)
  (* cancel: the credit is handed back *)
  | cancel n : lts (Idle, n) (Some Cancel) (Giving, n)
  (* brew inside of the machine, invisible to the customer *)
  | brew d n : lts (Brewing d, n) None (Ready d, n)
  (* serve the drink, return remaining credit as change *)
  | serve d n : lts (Ready d, n) (Some (Serve d)) (Giving, n)
  (* return excess credit as change *)
  | give c n : In c (change n) ->
      lts (Giving, n) (Some (Return c)) (Giving, n - value c)
  (* done when no more change to return *)
  | done : lts (Giving, 0) None (Idle, 0).

  (** *** Extraction

      A new machine starts idle, with no credit. All the machines in this file
      start that way, and only their rules differ. *)

  (* ANCHOR: extract-classic *)
  Definition classic : term := (Idle, 0).

  (* MeBi Config Output "DumpResults" True. *)
  MeBi Config Output Format Text.

  MeBi Run LTS classic Using lts.
  (* ANCHOR_END: extract-classic *)


  (* Draw the LTS above ([MeBi Help Draw], [MeBi Help Config Draw]). It writes
     TikZ, and a PDF if lualatex is installed, into ./_diagrams/ of the
     directory Rocq runs in: coffee-machine.tikz (the picture),
     coffee-machine.style.tikz (its styles) and coffee-machine.tex (draws the
     two), then coffee-machine.pdf.

     The picture sets no colour or shape itself: it names a style for each part
     and the style file defines them, from a default for each part followed by
     the options below, which win. The parts are Layout, State, Initial,
     Terminal, Edge, Label, SilentEdge, SilentLabel, TwoWay, Loop and Caption.
     Options are TikZ options; "" puts a part back to its default. *)
  MeBi Config Draw Format PDF.                    (* TeX | PDF | PNG *)
  (* MeBi Config Draw Dir "./_diagrams/". *)
  (* MeBi Config Bounds Draw States 50.           (* or Transitions <n>; Time <s> *) *)

  (* Examples to try, one at a time: *)
  (* MeBi Config Draw Style "Layout" "level distance=24mm, sibling distance=16mm". *)
  (* MeBi Config Draw Style "State" "fill=yellow!20". *)
  (* MeBi Config Draw Style "Edge" "thick, draw=blue!60!black". *)
  (* MeBi Config Draw Style "Label" "font=\tiny". *)
  (* MeBi Config Draw Style "Label" "draw=gray!50, rounded corners=1pt". *)
  (* MeBi Config Draw Style "Terminal" "fill=red!10". *)

  MeBi Draw LTS classic Using lts As "coffee-machine".

End Classic.


(** ** 2. The upgrade

    More drinks and a card reader. Tapping a card puts 50p of credit on the
    machine, so any change comes back as coins. The card is the only way to
    reach 50p, so the espresso is for card users only. Everything else is as in
    the classic machine. *)

Module Upgrade.

  Definition drinks : list drink := [tea; coffee; latte; espresso].

  Inductive mode : Set :=
  | Idle
  | Brewing (d : drink)
  | Ready   (d : drink)
  | Giving.

  Definition term : Set := mode * nat.

  Definition cap : nat := 30.

  Inductive lts : term -> option label -> term -> Prop :=
  | insert c n : In c coins -> Nat.leb (n + value c) cap = true ->
      lts (Idle, n) (Some (Insert c)) (Idle, n + value c)
  (* ANCHOR: upgrade-rules *)
  (* new: the card reader *)
  | tap :
      lts (Idle, 0) (Some Tap) (Idle, 50)
  (* new: more drinks *)
  | ask d n : In d drinks -> Nat.leb (price d) n = true ->
      lts (Idle, n) (Some (Ask d)) (Brewing d, n - price d)
  (* ANCHOR_END: upgrade-rules *)
  | cancel n :
      lts (Idle, n) (Some Cancel) (Giving, n)
  | brew d n :
      lts (Brewing d, n) None (Ready d, n)
  | serve d n :
      lts (Ready d, n) (Some (Serve d)) (Giving, n)
  | give c n : In c (change n) ->
      lts (Giving, n) (Some (Return c)) (Giving, n - value c)
  | done :
      lts (Giving, 0) None (Idle, 0).

  (* ANCHOR: extract-upgrade *)
  Definition upgrade : term := (Idle, 0).

  MeBi Run LTS upgrade Using lts.
  (* ANCHOR_END: extract-upgrade *)

  (** *** Proofs

      The upgrade simulates the classic machine: whatever the classic machine
      does, the upgrade can do too. It takes 256 steps, and [Solve] permits one
      more than its number, so 255 is the least bound that works. *)

  Example wsim_classic_upgrade :
    weak_sim Classic.lts lts Classic.classic upgrade.
  Proof.
    MeBi Sim Begin Classic.lts Classic.classic And lts upgrade.
    MeBi Sim Solve 255.
  Qed.

  (** Not the other way round: the upgrade can tap a card, or ask for a latte,
      and the classic machine cannot. [Sim Begin] checks before it starts, so
      the [Fail] is a decided "no". *)

  Example wsim_upgrade_classic :
    weak_sim lts Classic.lts upgrade Classic.classic.
  Proof.
    Fail MeBi Sim Begin lts upgrade And Classic.lts Classic.classic.
  Abort.

  (** The same "no", by deciding instead of proving, and with its reason.
      [FailIf NotBisimilar] is [True] by default, so [Run Sim] on a pair that
      is not similar is an error, and the error says why. [Fail] makes that
      a success; an editor shows the error it failed with, and [rocq compile]
      prints nothing. Set to [False] it would be a warning instead. *)

  (* ANCHOR: upgrade-failif *)
  MeBi Config FailIf NotBisimilar True. (* true by default *)
  Fail MeBi Run Sim upgrade With lts And Classic.classic With Classic.lts.
  (* ANCHOR_END: upgrade-failif *)

End Upgrade.


(** ** 3. The replica

    Built differently inside: it takes two silent steps to brew a drink,
    where the classic machine takes one. Nobody at the machine can tell. *)

Module Replica.

  Definition drinks : list drink := [tea; coffee].

  (** [Warm d] is used only by the replica: [d] has been heated, and is not yet
      made. *)

  Inductive mode : Set :=
  | Idle
  | Brewing (d : drink)
  | Warm    (d : drink)
  | Ready   (d : drink)
  | Giving.

  Definition term : Set := mode * nat.

  Definition cap : nat := 30.

  Inductive lts : term -> option label -> term -> Prop :=
  | insert c n : In c coins -> Nat.leb (n + value c) cap = true ->
      lts (Idle, n) (Some (Insert c)) (Idle, n + value c)
  | ask d n : In d drinks -> Nat.leb (price d) n = true ->
      lts (Idle, n) (Some (Ask d)) (Brewing d, n - price d)
  | cancel n :
      lts (Idle, n) (Some Cancel) (Giving, n)
  (* ANCHOR: replica-rules *)
  (* different: two silent steps, heat and then brew *)
  | heat d n :
      lts (Brewing d, n) None (Warm d, n)
  | brew d n :
      lts (Warm d, n) None (Ready d, n)
  (* ANCHOR_END: replica-rules *)
  | serve d n :
      lts (Ready d, n) (Some (Serve d)) (Giving, n)
  | give c n : In c (change n) ->
      lts (Giving, n) (Some (Return c)) (Giving, n - value c)
  | done :
      lts (Giving, 0) None (Idle, 0).

  (* ANCHOR: extract-replica *)
  Definition replica : term := (Idle, 0).

  MeBi Run LTS replica Using lts.
  (* ANCHOR_END: extract-replica *)

  (** *** Proofs

      The replica and the classic machine are weakly bisimilar: each can
      answer the other, and the extra silent step makes no difference to
      anyone at the machine. It takes 685 steps, so 684 is the least bound. *)

  Example wbis_classic_replica :
    weak_bisimilar Classic.lts lts Classic.classic replica.
  Proof.
    MeBi Sim Begin Classic.lts Classic.classic And lts replica.
    MeBi Sim Solve 684.
  Qed.

End Replica.


(** ** 4. The worn replica (a sketch, not compiled)

    Like the classic machine, except that while it is idle it can run out of
    coffee beans, and it does so silently. From then on it still takes coins
    and makes tea, but it cannot make coffee.

    Everything this machine does, the classic machine can do too, and the
    other way round, so what the two can do cannot tell them apart. But a
    customer can: the classic machine never refuses coffee to someone who has
    paid for it, and this one sometimes does.

    This is the earlier version of the section, from before the machines were
    split into modules, kept as it was and put in a comment so that it does not
    compile. To bring it back it needs rethinking as a module of its own:
    - a [NoBeans] state in its own [mode];
    - [drinks] in place of [old_drinks], and [cap] in place of the literal 50;
    - rules named as the other modules' (no [w_] prefix), and [classic] in
      place of [old] in the proofs;
    - proofs against [Classic.lts], as in [Upgrade] and [Replica]:
      [weak_sim] each way, [mutual_sim] from the two, and a [Fail] on
      [weak_bisimilar] (the classic and the worn machine are mutually similar,
      but not bisimilar).

    The step counts it was measured with are out of date: they were for
    prices and a cap that have since changed.

(*
Inductive lts_worn : term -> option label -> term -> Prop :=
| w_insert c n : In c coins -> Nat.leb (n + value c) 50 = true ->
    lts_worn (Idle, n) (Some (Insert c)) (Idle, n + value c)
| w_ask d n : In d old_drinks -> Nat.leb (price d) n = true ->
    lts_worn (Idle, n) (Some (Ask d)) (Brewing d, n - price d)
| w_cancel n :
    lts_worn (Idle, n) (Some Cancel) (Giving, n)
| w_brew d n :
    lts_worn (Brewing d, n) None (Ready d, n)
| w_serve d n :
    lts_worn (Ready d, n) (Some (Serve d)) (Giving, n)
| w_return c n : In c (change n) ->
    lts_worn (Giving, n) (Some (Return c)) (Giving, n - value c)
| w_done :
    lts_worn (Giving, 0) None (Idle, 0)
(* ANCHOR: worn-rules *)
(* different: silently running out of beans *)
| w_run_out n :
    lts_worn (Idle, n) None (NoBeans, n)
(* without beans: coins, cancel and tea still work, coffee does not *)
| w_nb_insert c n : In c coins -> Nat.leb (n + value c) 50 = true ->
    lts_worn (NoBeans, n) (Some (Insert c)) (NoBeans, n + value c)
| w_nb_tea n : Nat.leb (price tea) n = true ->
    lts_worn (NoBeans, n) (Some (Ask tea)) (Brewing tea, n - price tea)
| w_nb_cancel n :
    lts_worn (NoBeans, n) (Some Cancel) (Giving, n).
(* ANCHOR_END: worn-rules *)

(* ANCHOR: extract-worn *)
Definition worn : term := (Idle, 0).

MeBi Run LTS worn Using lts_worn.
(* ANCHOR_END: extract-worn *)
*) *)
