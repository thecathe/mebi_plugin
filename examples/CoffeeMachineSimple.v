
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
    | tea => 20
    | coffee => 30
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

  Definition cap : nat := 50.

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
    lts (Refunding None, n) None (Refunding (Some c), n)
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

MeBi Help Premises.

MeBi Run LTS old Using lts.

End classic.