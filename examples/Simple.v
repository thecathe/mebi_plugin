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

MeBi Config Output "DumpResults" True.
MeBi Config Output Format Text.

MeBi Run LTS init Using lts.

MeBi Config Draw Format PNG.                    (* TeX | PDF | PNG *)
MeBi Draw LTS init Using lts As "simple".
