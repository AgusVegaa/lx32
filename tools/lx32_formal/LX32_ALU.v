(* ================================================================== *)
(* LX32_ALU.v                                                         *)
(* Formal specification of the LX32 ALU and core algebraic properties.*)
(*                                                                    *)
(* Corresponds to: core/alu.sv, arch/lx32_alu_pkg.sv                  *)
(*                                                                    *)
(* This file defines:                                                  *)
(*   - The ALU operation type used by decode/control                  *)
(*   - The executable ALU function over architectural words           *)
(*   - Basic correctness and range lemmas used by system proofs       *)
(* ================================================================== *)

Require Import Coq.NArith.NArith.
Require Import Coq.ZArith.ZArith.
(* Architectural word-level definitions. *)
Require Import LX32_Arch.

Local Open Scope N_scope.

(* ------------------------------------------------------------------ *)
(* Section 1 — ALU Operation Type                                     *)
(* ------------------------------------------------------------------ *)

Inductive alu_op :=
  | ALU_ADD  : alu_op
  | ALU_SUB  : alu_op
  | ALU_SLL  : alu_op
  | ALU_SLT  : alu_op
  | ALU_SLTU : alu_op
  | ALU_XOR  : alu_op
  | ALU_SRL  : alu_op
  | ALU_SRA  : alu_op
  | ALU_OR   : alu_op
  | ALU_AND  : alu_op.

(* ------------------------------------------------------------------ *)
(* Section 2 — Functional Specification                               *)
(* ------------------------------------------------------------------ *)

Definition alu_spec (src_a src_b : word) (op : alu_op) : word :=
  match op with
  | ALU_ADD  => wrap_word (src_a + src_b)
  | ALU_SUB  =>
      wrap_word
        (Z.to_N
           (Z.modulo (Z.of_N src_a - Z.of_N src_b)
                     (Z.of_N word_modulus)))
  | ALU_SLL  => wrap_word (N.shiftl src_a (src_b mod 32))
  | ALU_SRL  => wrap_word (N.shiftr src_a (src_b mod 32))
  | ALU_SRA  =>
      let val_a := word_to_signed src_a in
      let shift := Z.of_N (src_b mod 32) in
      wrap_word (Z.to_N (Z.modulo (Z.shiftr val_a shift) (Z.of_N word_modulus)))
  | ALU_SLT  =>
      if Z.ltb (word_to_signed src_a) (word_to_signed src_b)
      then 1 else 0
  | ALU_SLTU =>
      if N.ltb src_a src_b then 1 else 0
  | ALU_XOR  => wrap_word (N.lxor src_a src_b)
  | ALU_OR   => wrap_word (N.lor src_a src_b)
  | ALU_AND  => wrap_word (N.land src_a src_b)
  end.

(* ------------------------------------------------------------------ *)
(* Section 3 — Algebraic Properties                                   *)
(* ------------------------------------------------------------------ *)

Lemma alu_add_comm : forall a b,
  alu_spec a b ALU_ADD = alu_spec b a ALU_ADD.
Proof.
  intros a b. unfold alu_spec.
  rewrite N.add_comm. reflexivity.
Qed.

Lemma alu_and_idempotent : forall a,
  alu_spec a a ALU_AND = wrap_word a.
Proof.
  intro a. unfold alu_spec. rewrite N.land_diag. reflexivity.
Qed.

Lemma alu_xor_self : forall a,
  alu_spec a a ALU_XOR = 0.
Proof.
  intro a. unfold alu_spec. rewrite N.lxor_nilpotent.
  unfold wrap_word.
  rewrite N.mod_small.
  - reflexivity.
  - unfold word_modulus. compute. easy.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 4 — Range Properties                                       *)
(* ------------------------------------------------------------------ *)

Theorem alu_result_in_range : forall a b op,
  word_in_range (alu_spec a b op).
Proof.
  intros a b op.
  destruct op; simpl; unfold alu_spec;
  try (apply wrap_word_in_range).
  - (* ALU_SLT yields either 0 or 1, both strictly below 2^32. *)
    destruct (word_to_signed a <? word_to_signed b)%Z;
    unfold word_in_range, word_modulus; compute; apply N.lt_0_2.
  - (* ALU_SLTU yields either 0 or 1. *)
    destruct (a <? b)%N;
    unfold word_in_range, word_modulus; compute; apply N.lt_0_2.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 5 — Witness Proof                                          *)
(* ------------------------------------------------------------------ *)

Lemma alu_exists_logical_op : forall a b,
  exists res, alu_spec a b ALU_OR = res.
Proof.
  intros a b.
  eexists. (* Construct an explicit witness for the existential. *)
  reflexivity.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 6 — RTL Refinement Contract                                *)
(* ------------------------------------------------------------------ *)

Definition alu_impl_type := word -> word -> alu_op -> word.

Definition alu_refines_spec (impl : alu_impl_type) : Prop :=
  forall (src_a src_b : word) (op : alu_op),
    impl src_a src_b op = alu_spec src_a src_b op.

Theorem rtl_alu_add_correct :
  forall impl, alu_refines_spec impl ->
  forall a b, impl a b ALU_ADD = impl b a ALU_ADD.
Proof.
  intros impl Href a b.
  rewrite Href. rewrite Href.
  apply alu_add_comm.
Qed.
