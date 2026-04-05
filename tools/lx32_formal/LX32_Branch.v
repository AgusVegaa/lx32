(* ================================================================== *)
(* LX32_Branch.v                                                      *)
(* Formal specification of the LX32 branch evaluation unit.           *)
(*                                                                    *)
(* Corresponds to: core/branch_unit.sv, arch/lx32_branch_pkg.sv       *)
(*                                                                    *)
(* This file defines:                                                  *)
(*   - Branch operation kinds                                          *)
(*   - Pure branch comparison semantics                                *)
(*   - Basic relational lemmas used by step/safety proofs             *)
(* ================================================================== *)

Require Import Coq.NArith.NArith.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
(* Import architectural primitives shared across modules. *)
Require Import LX32_Arch.

Local Open Scope N_scope.

(* ------------------------------------------------------------------ *)
(* Section 0 — Branch operation type                                  *)
(* ------------------------------------------------------------------ *)

Inductive branch_op : Type :=
  | BR_EQ   (* A == B *)
  | BR_NE   (* A != B *)
  | BR_LT   (* signed(A) < B *)
  | BR_GE   (* signed(A) >= B *)
  | BR_LTU  (* A < B (unsigned) *)
  | BR_GEU. (* A >= B (unsigned) *)

(* ------------------------------------------------------------------ *)
(* Section 1 — Branch comparison specification                        *)
(* ------------------------------------------------------------------ *)

Definition branch_compare (src_a src_b : word) (op : branch_op) : bool :=
  match op with
  | BR_EQ  => N.eqb src_a src_b
  | BR_NE  => negb (N.eqb src_a src_b)
  | BR_LT  => Z.ltb (word_to_signed src_a) (word_to_signed src_b)
  | BR_GE  => Z.geb (word_to_signed src_a) (word_to_signed src_b)
  | BR_LTU => N.ltb src_a src_b
  | BR_GEU => N.leb src_b src_a
  end.

Definition branch_taken_spec (src_a src_b : word)
                              (is_branch : bool)
                              (op : branch_op) : bool :=
  andb is_branch (branch_compare src_a src_b op).

(* ------------------------------------------------------------------ *)
(* Section 2 — Complementary Pairs                                    *)
(* ------------------------------------------------------------------ *)

Lemma beq_bne_complement :
  forall a b : word,
    branch_compare a b BR_NE = negb (branch_compare a b BR_EQ).
Proof.
  intros a b. unfold branch_compare. reflexivity.
Qed.

Lemma blt_bge_complement :
  forall a b : word,
    branch_compare a b BR_GE = negb (branch_compare a b BR_LT).
Proof.
  intros a b. unfold branch_compare.
  rewrite Z.geb_leb.
  (* Z.leb and Z.ltb are related by boolean negation. *)
  destruct (word_to_signed a <? word_to_signed b)%Z eqn:Hlt.
  - apply Z.ltb_lt in Hlt.
    assert (Hnle: (word_to_signed b <=? word_to_signed a)%Z = false).
    { apply Z.leb_gt. exact Hlt. }
    rewrite Hnle. reflexivity.
  - apply Z.ltb_ge in Hlt.
    assert (Hle: (word_to_signed b <=? word_to_signed a)%Z = true).
    { apply Z.leb_le. exact Hlt. }
    rewrite Hle. reflexivity.
Qed.

Lemma bltu_bgeu_complement :
  forall a b : word,
    branch_compare a b BR_GEU = negb (branch_compare a b BR_LTU).
Proof.
  intros a b. unfold branch_compare.
  destruct (a <? b)%N eqn:Hlt.
  - apply N.ltb_lt in Hlt.
    assert (Hnle: (b <=? a)%N = false).
    { apply N.leb_gt. exact Hlt. }
    rewrite Hnle. reflexivity.
  - apply N.ltb_ge in Hlt.
    assert (Hle: (b <=? a)%N = true).
    { apply N.leb_le. exact Hlt. }
    rewrite Hle. reflexivity.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 3 — Symmetry and Self-comparison                           *)
(* ------------------------------------------------------------------ *)

Lemma beq_symmetric :
  forall a b : word,
    branch_compare a b BR_EQ = branch_compare b a BR_EQ.
Proof.
  intros a b. unfold branch_compare. apply N.eqb_sym.
Qed.

Lemma beq_self :
  forall a : word, branch_compare a a BR_EQ = true.
Proof.
  intro a. unfold branch_compare. apply N.eqb_refl.
Qed.

Lemma blt_self :
  forall a : word, branch_compare a a BR_LT = false.
Proof.
  intro a. unfold branch_compare. apply Z.ltb_irrefl.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 4 — Gating and Refinement                                  *)
(* ------------------------------------------------------------------ *)

Lemma branch_not_taken_when_disabled :
  forall a b : word, forall op : branch_op,
    branch_taken_spec a b false op = false.
Proof. intros. reflexivity. Qed.

Definition branch_impl_type := word -> word -> branch_op -> bool.

Definition branch_refines_spec (impl : branch_impl_type) : Prop :=
  forall a b : word, forall op : branch_op,
    impl a b op = branch_compare a b op.

Theorem branch_impl_beq_bne_complement :
  forall impl : branch_impl_type,
    branch_refines_spec impl ->
    forall a b : word,
      impl a b BR_NE = negb (impl a b BR_EQ).
Proof.
  intros impl Href a b.
  rewrite Href, Href. apply beq_bne_complement.
Qed.
