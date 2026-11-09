Require Import MEBI.loader.
Require Import MEBI.Bisimilarity.
From Stdlib Require Import List Arith.
Import ListNotations.

(* Drawn by Graphviz, which needs `dot` on the PATH of the process running
   Rocq (the repository's nix dev shell provides it): without it only
   simple.dot is written, with a warning. *)
MeBi Config Draw Engine Graphviz.
MeBi Config Draw Format PNG.                    (* TeX | PDF | PNG *)
MeBi Config Draw Direction Right.               (* Down | Right: Right is landscape *)

Inductive ab : Set := A | B.
Record pair : Set := mkPair { l:ab; r:ab }.

Inductive what_exists : Set := O | x.
Definition this_exists : list what_exists := [O;x].

Inductive ac : Set := init | args.
Definition acs : list ac := [init;args].

Inductive state : Set :=
| Done
| NewProof (_ : ab) (_ : ab)
| OpenBlock
| WeakSim
| Exists (_ : what_exists)
| ApplyConstructors (_ : ac).

Inductive label : Set :=
| Unfold | MutualFix | Refl | Exact | NewCofix | Finished | Invert | NoInvert | Trans | ExIntro | Refute | Prove | Begin.

Inductive lts : state -> label -> state -> Prop :=
| newproof_unfold_weaksim a b : lts (NewProof a b) Unfold WeakSim
| newproof_unfold_openblock a b : lts (NewProof a b) Unfold OpenBlock
| openblock_unfold_weaksim : lts OpenBlock Unfold OpenBlock
| openblock_mutualfix_weaksim : lts OpenBlock MutualFix WeakSim
| weaksim_refl_weaksim : lts WeakSim Refl WeakSim
| weaksim_unfold_weaksim : lts WeakSim Unfold WeakSim
| weaksim_exact_weaksim : lts WeakSim Exact WeakSim
| weaksim_newcofix_weaksim : lts WeakSim NewCofix WeakSim
| weaksim_finished_done : lts WeakSim Finished Done
| weaksim_invert_weaksim : lts WeakSim Invert WeakSim
(* | weaksim_hypunfold_weaksim : lts WeakSim HypUnfold WeakSim *)
| weaksim_noinvert_existso : lts WeakSim NoInvert (Exists O)
| existso_trans_existsx : lts (Exists O) Trans (Exists x)
| existso_exintro_aci : lts (Exists O) ExIntro (ApplyConstructors init)
| existso_refute_weaksim : lts (Exists O) Refute WeakSim
| existsx_exintro_weaksim : lts (Exists x) ExIntro (Exists x)
| existsx_exintro_aci : lts (Exists x) ExIntro (ApplyConstructors init)
| existsx_refl_weaksim : lts (Exists x) Refl WeakSim
| exists0_refl_weaksim : lts (Exists x) Refl WeakSim
| aci_begin_aca : lts (ApplyConstructors init) Begin (ApplyConstructors args)
| aca_refl_aca : lts (ApplyConstructors args) Refl (ApplyConstructors args)
| aca_prove_aca : lts (ApplyConstructors args) Prove (ApplyConstructors args)
| aca_refl_weaksim : lts (ApplyConstructors args) Refl WeakSim
.

MeBi Config Reset Weak.

MeBi Config Output "DumpResults" True.
MeBi Config Output Format Text.

MeBi Run LTS (NewProof A B) Using lts.

(* Drawn by Graphviz, which needs `dot` on the PATH of the process running
   Rocq (the repository's nix dev shell provides it): without it only
   simple.dot is written, with a warning. *)
MeBi Config Draw Engine Graphviz.
MeBi Config Draw Format PNG.                    (* TeX | PDF | PNG *)
MeBi Config Draw Direction Right.               (* Down | Right: Right is landscape *)

(* Colour is by kind of label, the first word of it ("Insert" for "Insert ten"),
   and only where set. *)
(* MeBi Config Draw Kind "Select" "green!50!black".
MeBi Config Draw Kind "Insert" "blue!75!black".
MeBi Config Draw Kind "Output" "orange!90!black". *)

MeBi Draw LTS (NewProof A B) Using lts As "proof-solver-right".

MeBi Config Draw Direction Down.               (* Down | Right: Right is landscape *)
MeBi Draw LTS (NewProof A B) Using lts As "proof-solver-down".
