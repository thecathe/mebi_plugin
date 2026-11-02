Require Import MEBI.loader.
Require Import MEBI.Bisimilarity.
From Stdlib Require Import List Arith.
Import ListNotations.

Inductive coin : Set := ten.
Definition coins : list coin := [ten].
Definition value (c : coin) : nat :=
match c with | ten => 10 end.

Inductive drink : Set := tea | coffee.
Definition drinks : list drink := [coffee].
Definition price (d : drink) : nat :=
match d with | tea => 10 | coffee => 20 end.

Inductive interface : Set :=
| Select (d : drink)
| Insert (c : coin)
| Output (d : drink).

MeBi Config Weak As Option interface.

Inductive mode : Set :=
| Idle
| Paid (n : nat) (d : drink)
| Ready (d : drink).

Inductive lts : mode -> option interface -> mode -> Prop :=
| select  d : In d drinks -> lts Idle (Some (Select d)) (Paid 0 d)
| output  d : In d drinks -> lts (Ready d) (Some (Output d)) Idle
| prepare d n : In d drinks -> Nat.eqb n (price d) = true -> lts (Paid n d) None (Ready d)
| payment d n c : In d drinks -> In c coins -> Nat.leb (n + value c) (price d) = true ->
              lts (Paid n d) (Some (Insert c)) (Paid (n + value c) d).

Definition init : mode := Idle.

(* MeBi Config Output "DumpResults" True. *)
(* MeBi Config Output Format Text. *)

MeBi Run LTS init Using lts.

(* Drawn by Graphviz, which needs `dot` on the PATH of the process running
   Rocq (the repository's nix dev shell provides it): without it only
   simple.dot is written, with a warning. *)
MeBi Config Draw Engine Graphviz.
MeBi Config Draw Format PNG.                    (* TeX | PDF | PNG *)
MeBi Config Draw Direction Right.               (* Down | Right: Right is landscape *)

(* Colour is by kind of label, the first word of it ("Insert" for "Insert ten"),
   and only where set. *)
MeBi Config Draw Kind "Select" "green!50!black".
MeBi Config Draw Kind "Insert" "blue!75!black".
MeBi Config Draw Kind "Output" "orange!90!black".

MeBi Draw LTS init Using lts As "0simple-right".

MeBi Config Draw Direction Down.               (* Down | Right: Right is landscape *)
MeBi Draw LTS init Using lts As "0simple-down".


Definition drinks_upgrade : list drink := [coffee;tea].

Inductive lts_upgrade : mode -> option interface -> mode -> Prop :=
| select'  d : In d drinks_upgrade -> lts_upgrade Idle (Some (Select d)) (Paid 0 d)
| output'  d : In d drinks_upgrade -> lts_upgrade (Ready d) (Some (Output d)) Idle
| prepare' d n : In d drinks_upgrade -> Nat.eqb n (price d) = true -> lts_upgrade (Paid n d) None (Ready d)
| payment' d n c : In d drinks_upgrade -> In c coins -> Nat.leb (n + value c) (price d) = true ->
              lts_upgrade (Paid n d) (Some (Insert c)) (Paid (n + value c) d).

(* MeBi Config Output "DumpResults" True.
MeBi Config Output Format Text. *)

MeBi Run LTS init Using lts_upgrade.
MeBi Config Draw Format PNG.                    (* TeX | PDF | PNG *)

MeBi Draw LTS init Using lts_upgrade As "0simple-upgrade-down".

MeBi Config Draw Direction Right.               (* Down | Right: Right is landscape *)
MeBi Draw LTS init Using lts_upgrade As "0simple-upgrade-right".


