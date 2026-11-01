
Require Import MEBI.loader.
From Stdlib Require Import List Arith.
Import ListNotations.

Inductive coin : Set := ten | twenty | fifty.
Definition coins : list coin := [fifty;twenty;ten].

Definition value (x : coin) : nat :=
  match x with
  | ten => 10
  | twenty => 20
  | fifty => 50
  end.

Definition coin_fits (n : nat) (c : coin) : bool := Nat.leb (value c) n.

Fixpoint biggest_fitting_coin (n : nat) (cs : list coin) : option coin :=
  match cs with
  | [] => None
  | c::cs =>
    if coin_fits n c then Some c
    else biggest_fitting_coin n cs
  end.

Definition biggest_coin (n : nat) : option coin := biggest_fitting_coin n coins.

Definition refund_coin (x : coin) (n : nat) : option nat :=
  if Nat.leb (value x) n then Some (n - (value x)) else None.

Fixpoint to_coins (n : nat) (xs : list coin) : list coin :=
  match xs with
  | [] => []
  | x::xs =>
    match refund_coin x n with
    | None => to_coins n xs
    | Some r => x::(to_coins r xs)
    end
  end.

Definition change (n : nat) : list coin := to_coins n coins.

Section classic.

  Inductive drink : Set := tea | coffee.
  Definition drinks : list drink := [coffee;tea].

  Definition price (x : drink) : nat :=
    match x with
    | tea => 10
    | coffee => 20
    end.

  Inductive label : Set :=
  | Insert (c : coin)
  | Select (d : drink)
  | Serve (d : drink)
  | Return (c : coin)
  | Cancel.

  Inductive mode : Set :=
  | Idle
  | Brewing (d : drink)
  | Ready (d : drink)
  | Serving
  | Refunding (c : option coin).

  Definition term : Set := mode * nat.

  Definition cap : nat := 30.

  Definition within_price_cap (n : nat) (c : coin) : Prop :=
    Nat.leb (n + value c) cap = true.

  Definition affordable_drink (n : nat) (d : drink) : Prop :=
    Nat.leb (price d) n = true.

  Search option.

  Inductive lts : term -> option label -> term -> Prop :=
  | insert c n : In c coins -> Nat.leb (n + value c) cap = true ->
    lts (Idle, n) (Some (Insert c)) (Idle, n + value c)
  | select d n : In d drinks -> Nat.leb (price d) n = true ->
    lts (Idle, n) (Some (Select d)) (Brewing d, n - price d)
  | brew  d n : lts (Brewing d, n) None (Ready d, n)
  | serve d n : lts (Ready d, n) (Some (Serve d)) (Serving, n)
  | refunding n : lts (Serving, n) None (Refunding None, n)
  | calculate n c : In c coins -> biggest_coin n = Some c ->
    lts (Refunding None, n) None (Refunding (Some c), n - (value c))
  | do_refund c n : lts (Refunding (Some c), n) (Some (Return c)) (Refunding None, n)
  | done : lts (Refunding None, 0) None (Idle, 0)
  (* | refund_50 cs n r : (refund_coin fifty n) = Some r ->
    lts (Refunding cs, n) None (Refunding (fifty::cs), r)
  | refund_20 cs n r : (refund_coin twenty n) = Some r ->
    lts (Refunding cs, n) None (Refunding (twenty::cs), r)
  | refund_10 cs n r : (refund_coin ten n) = Some r ->
    lts (Refunding cs, n) None (Refunding (ten::cs), r) *)
  .


Definition old : term := (Idle, 0).

MeBi Config Weak As Option label.
MeBi Config Output "DumpResults" True.
MeBi Config Output Format Text.

MeBi Config Output "Result" True.
MeBi Config Output Wrap Flow.

MeBi Help Premises.

MeBi Run LTS old Using lts.

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

MeBi Draw LTS old Using lts As "coffee-machine-simple".

End classic.