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
| Output (d : drink)
| ChipNPin.

(* ANCHOR: config-reset-weak *)
MeBi Config Reset Weak.
(* ANCHOR_END: config-reset-weak *)

(* ANCHOR: config-weak *)
MeBi Config Weak As Option interface.
(* ANCHOR_END: config-weak *)

Inductive mode : Set :=
| Idle
| Paid (n : nat) (d : drink)
| Warm (d : drink) (* replica only *)
| Ready (d : drink)
| NoBeans (* worn replica only *).

Inductive lts_c : mode -> option interface -> mode -> Prop :=
| c_select d : In d drinks ->
    lts_c Idle (Some (Select d)) (Paid 0 d)
| c_output d : In d drinks ->
    lts_c (Ready d) (Some (Output d)) Idle
| c_prepare d n : In d drinks ->
    Nat.eqb n (price d) = true ->
    lts_c (Paid n d) None (Ready d)
| c_payment d n c : In d drinks -> In c coins ->
    Nat.leb (n + value c) (price d) = true ->
    lts_c (Paid n d) (Some (Insert c)) (Paid (n + value c) d).

Inductive lts_u : mode -> option interface -> mode -> Prop :=
| u_select d : In d drinks ->
    lts_u Idle (Some (Select d)) (Paid 0 d)
| u_output d : In d drinks ->
    lts_u (Ready d) (Some (Output d)) Idle
| u_prepare d n : In d drinks ->
    Nat.eqb n (price d) = true ->
    lts_u (Paid n d) None (Ready d)
| u_chip d : In d drinks ->
    lts_u (Paid 0 d) (Some ChipNPin) (Paid (price d) d)
| u_payment d n c : In d drinks -> In c coins ->
    Nat.leb (n + value c) (price d) = true ->
    lts_u (Paid n d) (Some (Insert c)) (Paid (n + value c) d).

Inductive lts_r : mode -> option interface -> mode -> Prop :=
| r_select d : In d drinks ->
    lts_r Idle (Some (Select d)) (Paid 0 d)
| r_output d : In d drinks ->
    lts_r (Ready d) (Some (Output d)) Idle
| r_heat d n : In d drinks ->
    Nat.eqb n (price d) = true ->
    lts_r (Paid n d) None (Warm d)
| r_prepare d : In d drinks ->
    lts_r (Warm d) None (Ready d)
| r_payment d n c : In d drinks -> In c coins ->
    Nat.leb (n + value c) (price d) = true ->
    lts_r (Paid n d) (Some (Insert c)) (Paid (n + value c) d).

Inductive lts_w : mode -> option interface -> mode -> Prop :=
| w_select d : In d drinks ->
    lts_w Idle (Some (Select d)) (Paid 0 d)
| w_output d : In d drinks ->
    lts_w (Ready d) (Some (Output d)) Idle
| w_prepare d n : In d drinks ->
    Nat.eqb n (price d) = true ->
    lts_w (Paid n d) None (Ready d)
| w_payment d n c : In d drinks -> In c coins ->
    Nat.leb (n + value c) (price d) = true ->
    lts_w (Paid n d) (Some (Insert c)) (Paid (n + value c) d)
| w_run_out :
    lts_w Idle None NoBeans.


(* ANCHOR: extraction *)
MeBi Config Output "DumpResults" True.
MeBi Config Output "Info" True.
MeBi Config Output Format JSON.
MeBi Run LTS Idle Using lts_c.  (* classic *)
MeBi Run LTS Idle Using lts_u.  (* upgrade *)
MeBi Run LTS Idle Using lts_r.  (* replica *)
MeBi Run LTS Idle Using lts_w.  (* worn replica *)
(* ANCHOR_END: extraction *)

(* ANCHOR: graphviz-setup *)
(* Drawn by Graphviz, which needs `dot` on the PATH of the process running
   Rocq (the repository's nix dev shell provides it): without it only
   simple.dot is written, with a warning. *)
MeBi Config Draw Engine Graphviz.
MeBi Config Draw Format PNG.                    (* TeX | PDF | PNG *)

(* Colour is by kind of label, the first word of it ("Insert" for "Insert ten"),
   and only where set. *)
MeBi Config Draw Kind "Select" "green!50!black".
MeBi Config Draw Kind "Insert" "blue!75!black".
MeBi Config Draw Kind "Output" "orange!90!black".
MeBi Config Draw Kind "ChipNPin" "red!75!black".
(* ANCHOR_END: graphviz-setup *)

(* ANCHOR: graphviz-right *)
MeBi Config Draw Direction Right.               (* Down | Right: Right is landscape *)

MeBi Draw LTS Idle Using lts_c As "Exa-simple-CM-classic-r".
MeBi Draw LTS Idle Using lts_u As "Exa-simple-CM-upgrade-r".
(* ANCHOR_END: graphviz-right *)


(* ANCHOR: graphviz-down *)
MeBi Config Draw Direction Down.               (* Down | Right: Right is landscape *)

MeBi Draw LTS Idle Using lts_c As "Exa-simple-CM-classic-d".
MeBi Draw LTS Idle Using lts_u As "Exa-simple-CM-upgrade-d".
(* ANCHOR_END: graphviz-down *)

MeBi Config Output "Info" False.

Example wsim_classic_upgrade :
  weak_sim lts_c lts_u Idle Idle.
Proof.
  MeBi Sim Begin lts_c Idle And lts_u Idle.
  MeBi Sim Step.
  MeBi Sim Solve 57.
  MeBi Sim Step.
Qed.

Example wsim_upgrade_classic :
  weak_sim lts_u lts_c Idle Idle.
Proof.
  Fail MeBi Sim Begin lts_u Idle And lts_c Idle.
Abort.

(* ANCHOR: upgrade-failif *)
MeBi Config FailIf NotBisimilar True. (* default: True *)
Fail MeBi Run Sim Idle With lts_u And Idle With lts_c.
(* ANCHOR_END: upgrade-failif *)

Example wbis_classic_replica :
  weak_bisimilar lts_c lts_r Idle Idle.
Proof.
  MeBi Sim Begin lts_c Idle And lts_r Idle.
  MeBi Sim Solve 167.
Qed.

(* ANCHOR: replica-strong *)
MeBi Config Reset Weak. (* mode: strong *)
Fail MeBi Run Bisim Idle With lts_c And Idle With lts_r.
(* ANCHOR_END: replica-strong *)

(* ANCHOR: worn-mutual *)
MeBi Config Weak As Option interface. (* mode: weak *)

Example wsim_classic_worn :
  weak_sim lts_c lts_w Idle Idle.
Proof.
  MeBi Sim Begin lts_c Idle And lts_w Idle.
  MeBi Sim Solve 59.
Qed.

Example wsim_worn_classic :
  weak_sim lts_w lts_c Idle Idle.
Proof.
  MeBi Sim Begin lts_w Idle And lts_c Idle.
  MeBi Sim Solve 63.
Qed.

Example msim_classic_worn :
  mutual_sim lts_c lts_w Idle Idle.
Proof.
  split; [exact wsim_classic_worn | exact wsim_worn_classic].
Qed.

Fail MeBi Run Bisim Idle With lts_c And Idle With lts_w.
(* ANCHOR_END: worn-mutual *)





