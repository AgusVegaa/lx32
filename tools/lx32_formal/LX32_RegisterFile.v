(* ================================================================== *)
(* LX32_RegisterFile.v                                                *)
(* Register-file behavioral lemmas for the LX32 architectural model.  *)
(*                                                                    *)
(* Corresponds to: core/register_file.sv, core/reg_generic.sv         *)
(*                                                                    *)
(* This file defines:                                                  *)
(*   - One-hot write characterization                                  *)
(*   - Read-after-write and non-interference lemmas                    *)
(*   - x0 hardwired-zero preservation properties                       *)
(* ================================================================== *)

Require Import Coq.NArith.NArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Arith.Arith.
Require Import Coq.micromega.Lia. (* Arithmetic automation for inequalities. *)
Require Import LX32_Arch.

(* ------------------------------------------------------------------ *)
(* Section 0 — One-hot write decoder                                  *)
(* ------------------------------------------------------------------ *)

Definition at_most_one_write (rf_old rf_new : reg_file) : Prop :=
  exists addr : nat,
    forall i : nat,
      rf_old i <> rf_new i -> i = addr.

Lemma rf_write_is_one_hot :
  forall rf : reg_file, forall addr : nat, forall val : word,
    at_most_one_write rf (rf_write rf addr val).
Proof.
  intros rf addr val.
  unfold at_most_one_write.
  exists addr.
  intros i Hi.
  unfold rf_write in Hi.
  destruct (Nat.eqb addr 0%nat) eqn:Haddr0.
  - exfalso. apply Hi. reflexivity.
  - destruct (Nat.ltb addr REG_COUNT) eqn:Hrange.
    + simpl in Hi.
      destruct (Nat.eqb i addr) eqn:Heqi.
      * apply Nat.eqb_eq in Heqi. exact Heqi.
      * exfalso. apply Hi. reflexivity.
    + exfalso. apply Hi. reflexivity.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 1 — Read-after-write                                       *)
(* ------------------------------------------------------------------ *)

Lemma rf_write_read_same :
  forall rf : reg_file, forall addr : nat, forall val : word,
    addr <> 0%nat ->
    (addr < REG_COUNT)%nat ->
    rf_read (rf_write rf addr val) addr = wrap_word val.
Proof.
  intros rf addr val Hne Hlt.
  unfold rf_write, rf_read.
  destruct (Nat.eqb addr 0%nat) eqn:H0.
  - apply Nat.eqb_eq in H0. lia.
  - destruct (Nat.ltb addr REG_COUNT) eqn:Hlt'.
    + simpl. rewrite Nat.eqb_refl. reflexivity.
    + apply Nat.ltb_ge in Hlt'. lia.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 2 — Non-interference                                       *)
(* ------------------------------------------------------------------ *)

Lemma rf_write_read_different :
  forall rf : reg_file, forall addr i : nat, forall val : word,
    i <> addr ->
    rf_read (rf_write rf addr val) i = rf_read rf i.
Proof.
  intros rf addr i val Hne.
  unfold rf_write, rf_read.
  destruct (Nat.eqb addr 0%nat) eqn:H0.
  - reflexivity.
  - destruct (Nat.ltb addr REG_COUNT) eqn:Hlt_range.
    + simpl.
      destruct (Nat.eqb i addr) eqn:Heqi.
      * apply Nat.eqb_eq in Heqi. lia.
      * reflexivity.
    + reflexivity.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 3 — x0 Invariant                                           *)
(* ------------------------------------------------------------------ *)

Lemma rf_write_x0_noop :
  forall rf : reg_file, forall val : word,
    rf_write rf 0%nat val = rf.
Proof.
  intros rf val. unfold rf_write. simpl. reflexivity.
Qed.

Lemma rf_x0_invariant :
  forall rf : reg_file,
    rf_wf rf ->
    forall addr : nat, forall val : word,
      rf_wf (rf_write rf addr val).
Proof.
  intros rf Hwf addr val.
  destruct (Nat.eqb addr 0%nat) eqn:H0.
  - apply Nat.eqb_eq in H0. subst.
    rewrite rf_write_x0_noop. exact Hwf.
  - apply Nat.eqb_neq in H0.
    apply rf_write_nonzero_wf; assumption.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 4 — Consistency Theorem                                    *)
(* ------------------------------------------------------------------ *)

Theorem rf_write_read_consistency :
  forall rf : reg_file, forall addr i : nat, forall val : word,
    rf_write rf addr val i =
      if andb (Nat.eqb i addr)
              (andb (negb (Nat.eqb addr 0%nat))
                    (Nat.ltb addr REG_COUNT))
      then wrap_word val
      else rf i.
Proof.
  intros rf addr i val.
  unfold rf_write.
  destruct (Nat.eqb addr 0%nat) eqn:H0; simpl.
  - destruct (Nat.eqb i addr) eqn:Hi.
    + apply Nat.eqb_eq in H0, Hi. subst. reflexivity.
    + reflexivity.
  - destruct (Nat.ltb addr REG_COUNT) eqn:Hlt; simpl.
    + destruct (Nat.eqb i addr) eqn:Hi; reflexivity.
    + destruct (Nat.eqb i addr) eqn:Hi; reflexivity.
Qed.
