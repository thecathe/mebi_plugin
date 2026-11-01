(** * A coffee machine, its upgrade and its replicas

    The running example of the MeBi talk.

    1. The classic machine: coins in, a drink out, change back.
    2. The upgrade: more drinks and a card reader. It should do everything
       the classic machine does.
    3. The replica: the classic machine, built differently inside. It should
       behave the same.
    4. The worn replica: a replica that can silently run out of coffee beans.
       It should look the same too, but it is not quite the same.

    The machines are written out in full, one section each. The proofs are at
    the bottom. *)

Require Import MEBI.loader.
From Stdlib Require Import List Arith.
Import ListNotations.


(** ** 1. The classic machine *)

(** *** Coins, drinks and prices

    Money is counted in pence. Coins, prices and credit are all multiples of
    10p, so change can always be made with the coins we have.

    The machine compares behaviour over a single set of labels, so [drink]
    already holds the drinks of the upgrade. The classic machine just never
    offers [latte] or [espresso]. *)

Inductive coin : Set := ten | twenty | fifty.

Inductive drink : Set := tea | coffee | latte | espresso.

Definition value (c : coin) : nat :=
  match c with ten => 10 | twenty => 20 | fifty => 50 end.

Definition price (d : drink) : nat :=
  match d with tea => 20 | coffee => 30 | latte => 40 | espresso => 50 end.

(** The coins and drinks the machine accepts, as lists. The rules below use
    them to say which coin or drink a rule is about. *)

Definition coins : list coin := [ten; twenty; fifty].

Definition old_drinks : list drink := [tea; coffee].

(** The coin handed back when [n] pence is owed: the largest that fits, and
    none when nothing is owed. It is a list so that it can be used as a
    premise below, as [In c (change n)]. *)

Definition change (n : nat) : list coin :=
  if Nat.leb 50 n then [fifty]
  else if Nat.leb 20 n then [twenty]
  else if Nat.leb 10 n then [ten]
  else [].


(** *** Labels: what a person at the machine can see

    The user puts coins in ([Insert]), asks for a drink ([Ask]) or cancels
    ([Cancel]). The machine hands over a drink ([Serve]) and hands back coins
    ([Return]), whether that is a refund or change. [Tap] is only for the
    upgrade's card reader. Everything else the machine does is silent. *)

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

(** *** States

    A state is what the machine is doing, and how much money it holds for the
    customer (its credit). Only the sum matters, not the order the coins went
    in, so the credit is a single number.

    - [Idle]: waiting for coins and a request.
    - [Brewing d]: [d] was asked for, and is being made (silently).
    - [Ready d]: [d] is ready to be served.
    - [Giving]: handing back what is left of the credit, a coin at a time.
    - [Warm d]: used only by the replica, in section 3.
    - [NoBeans]: used only by the worn replica, in section 4. *)

Inductive mode : Set :=
| Idle
| Brewing (d : drink)
| Warm    (d : drink)
| Ready   (d : drink)
| Giving
| NoBeans.

Definition term : Set := mode * nat.


(** *** Semantics

    The credit is capped at 50p. The [In ...] premises matter: nothing else
    says which [c] or [d] a rule is about, and the plugin cannot guess. *)

Inductive lts_old : term -> option label -> term -> Prop :=
(* insert coins up to cap of 50 *)
| o_insert c n : In c coins -> Nat.leb (n + value c) 50 = true ->
    lts_old (Idle, n) (Some (Insert c)) (Idle, n + value c)
(* ask for drink: price taken from credit (must have enough) *)
| o_ask d n : In d old_drinks -> Nat.leb (price d) n = true ->
    lts_old (Idle, n) (Some (Ask d)) (Brewing d, n - price d)
(* cancel: the credit is handed back *)
| o_cancel n : lts_old (Idle, n) (Some Cancel) (Giving, n)
(* brew inside of the machine, invisible to the customer *)
| o_brew d n : lts_old (Brewing d, n) None (Ready d, n)
(* serve the drink, return remaining credit as change *)
| o_serve d n : lts_old (Ready d, n) (Some (Serve d)) (Giving, n)
(* return excess credit as change *)
| o_return c n : In c (change n) ->
    lts_old (Giving, n) (Some (Return c)) (Giving, n - value c)
(* done when no more change to return *)
| o_done : lts_old (Giving, 0) None (Idle, 0).


(** *** Extraction

    A new machine starts idle, with no credit. All the machines in this file
    start in the same state, and only their rules differ. *)

(* ANCHOR: extract-old *)
Definition old : term := (Idle, 0).

MeBi Config Output "DumpResults" True.
MeBi Config Output Format Text.

MeBi Run LTS old Using lts_old.
(* ANCHOR_END: extract-old *)


(** ** 2. The upgrade

    More drinks ([new_drinks]) and a card reader. Tapping a card puts 50p of
    credit on the machine, so any change comes back as coins. Everything else
    is as in the classic machine. *)

Definition new_drinks : list drink := [tea; coffee; latte; espresso].

Inductive lts_new : term -> option label -> term -> Prop :=
| n_insert c n : In c coins -> Nat.leb (n + value c) 50 = true ->
    lts_new (Idle, n) (Some (Insert c)) (Idle, n + value c)
(* ANCHOR: new-rules *)
(* new: the card reader *)
| n_tap :
    lts_new (Idle, 0) (Some Tap) (Idle, 50)
(* new: more drinks *)
| n_ask d n : In d new_drinks -> Nat.leb (price d) n = true ->
    lts_new (Idle, n) (Some (Ask d)) (Brewing d, n - price d)
(* ANCHOR_END: new-rules *)
| n_cancel n :
    lts_new (Idle, n) (Some Cancel) (Giving, n)
| n_brew d n :
    lts_new (Brewing d, n) None (Ready d, n)
| n_serve d n :
    lts_new (Ready d, n) (Some (Serve d)) (Giving, n)
| n_return c n : In c (change n) ->
    lts_new (Giving, n) (Some (Return c)) (Giving, n - value c)
| n_done :
    lts_new (Giving, 0) None (Idle, 0).

(* ANCHOR: extract-new *)
Definition new : term := (Idle, 0).

MeBi Run LTS new Using lts_new.
(* ANCHOR_END: extract-new *)


(** ** 3. The replica

    Built differently inside: it takes two silent steps to brew a drink,
    where the classic machine takes one. Nobody at the machine can tell. *)

Inductive lts_replica : term -> option label -> term -> Prop :=
| r_insert c n : In c coins -> Nat.leb (n + value c) 50 = true ->
    lts_replica (Idle, n) (Some (Insert c)) (Idle, n + value c)
| r_ask d n : In d old_drinks -> Nat.leb (price d) n = true ->
    lts_replica (Idle, n) (Some (Ask d)) (Brewing d, n - price d)
| r_cancel n :
    lts_replica (Idle, n) (Some Cancel) (Giving, n)
(* ANCHOR: replica-rules *)
(* different: two silent steps, heat and then brew *)
| r_heat d n :
    lts_replica (Brewing d, n) None (Warm d, n)
| r_brew d n :
    lts_replica (Warm d, n) None (Ready d, n)
(* ANCHOR_END: replica-rules *)
| r_serve d n :
    lts_replica (Ready d, n) (Some (Serve d)) (Giving, n)
| r_return c n : In c (change n) ->
    lts_replica (Giving, n) (Some (Return c)) (Giving, n - value c)
| r_done :
    lts_replica (Giving, 0) None (Idle, 0).

(* ANCHOR: extract-replica *)
Definition replica : term := (Idle, 0).

MeBi Run LTS replica Using lts_replica.
(* ANCHOR_END: extract-replica *)


(** ** 4. The worn replica

    Like the classic machine, except that while it is idle it can run out of
    coffee beans, and it does so silently. From then on it still takes coins
    and makes tea, but it cannot make coffee.

    Everything this machine does, the classic machine can do too, and the
    other way round, so what the two can do cannot tell them apart. But a
    customer can: the classic machine never refuses coffee to someone who has
    paid for it, and this one sometimes does. *)

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


(** ** 5. Proofs *)

Require Import MEBI.Bisimilarity.

(* Measured steps for [MeBi Sim Solve], with all machines starting at
   [(Idle, 0)]:

     [weak_sim lts_old lts_new old new]               about  400
     [weak_bisimilar lts_old lts_replica old replica] about 1,050
     [weak_sim lts_old lts_worn old worn]             about  400
     [weak_sim lts_worn lts_old worn old]             about  630

   Refused, because they do not hold: [weak_sim lts_new lts_old new old], and
   [weak_bisimilar lts_old lts_worn old worn] (the classic and the worn machine
   are mutually similar, but not bisimilar). *)
