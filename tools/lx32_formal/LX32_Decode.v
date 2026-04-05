(* ================================================================== *)
(* LX32_Decode.v                                                       *)
(* Formal specification of instruction field extraction and immediates.*)
(*                                                                    *)
(* Corresponds to: core/imm_gen.sv, arch/lx32_decode_pkg.sv,          *)
(*                arch/lx32_isa_pkg.sv                                 *)
(*                                                                    *)
(* This file defines:                                                  *)
(*   - Opcode decoding from raw instruction bits                       *)
(*   - Register/funct field extraction                                 *)
(*   - I/S/B/U/J immediate generation                                  *)
(* ================================================================== *)

Require Import Coq.NArith.NArith.
Require Import Coq.NArith.Nnat.    (* For N2Nat conversion lemmas. *)
Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Arith.Arith.
Require Import Coq.micromega.Lia.
Require Import LX32_Arch.

Local Open Scope N_scope.

(* ------------------------------------------------------------------ *)
(* Section 0 — Opcode type                                            *)
(* ------------------------------------------------------------------ *)

Inductive opcode : Type :=
  | OP_LUI
  | OP_AUIPC
  | OP_JAL
  | OP_JALR
  | OP_BRANCH
  | OP_LOAD
  | OP_STORE
  | OP_OP_IMM
  | OP_OP
  | OP_INVALID.

(* Use `%N` literals so opcode constants match the `N` type. *)
Definition decode_opcode (raw : N) : opcode :=
  match raw with
  | 55%N  => OP_LUI
  | 23%N  => OP_AUIPC
  | 111%N => OP_JAL
  | 103%N => OP_JALR
  | 99%N  => OP_BRANCH
  | 3%N   => OP_LOAD
  | 35%N  => OP_STORE
  | 19%N  => OP_OP_IMM
  | 51%N  => OP_OP
  | _     => OP_INVALID
  end.

(* ------------------------------------------------------------------ *)
(* Section 1 — Instruction field extraction                           *)
(* ------------------------------------------------------------------ *)

Definition extract_bits (w : word) (lo hi : nat) : N :=
  N.land (N.shiftr w (N.of_nat lo))
         (N.ones (N.of_nat (hi - lo + 1))).

Definition instr_opcode (instr : word) : N := extract_bits instr 0 6.

Definition instr_rd (instr : word) : nat :=
  Nat.modulo (N.to_nat (extract_bits instr 7 11)) REG_COUNT.

Definition instr_rs1 (instr : word) : nat :=
  Nat.modulo (N.to_nat (extract_bits instr 15 19)) REG_COUNT.

Definition instr_rs2 (instr : word) : nat :=
  Nat.modulo (N.to_nat (extract_bits instr 20 24)) REG_COUNT.

Definition instr_funct3 (instr : word) : N := extract_bits instr 12 14.

Definition instr_funct7_5 (instr : word) : bool :=
  N.testbit instr 30.

Definition instr_sign_bit (instr : word) : bool :=
  N.testbit instr 31.

Definition sign_extend (n : nat) (val : N) : word :=
  let msb := N.testbit val (N.of_nat (n - 1)) in
  if msb
  then wrap_word (N.lor val (N.shiftl (N.ones 32) (N.of_nat n)))
  else wrap_word val.

(* ------------------------------------------------------------------ *)
(* Section 2 — Immediate decoders                                     *)
(* ------------------------------------------------------------------ *)

Definition get_i_imm (instr : word) : word :=
  sign_extend 12 (extract_bits instr 20 31).

Definition get_s_imm (instr : word) : word :=
  let hi := extract_bits instr 25 31 in
  let lo := extract_bits instr 7  11 in
  sign_extend 12 (N.lor (N.shiftl hi 5) lo).

Definition get_b_imm (instr : word) : word :=
  let b12 := N.b2n (N.testbit instr 31) in
  let b11 := N.b2n (N.testbit instr 7)  in
  let b10_5 := extract_bits instr 25 30 in
  let b4_1  := extract_bits instr 8  11 in
  let raw := N.lor (N.shiftl b12 12)
            (N.lor (N.shiftl b11 11)
            (N.lor (N.shiftl b10_5 5)
                   (N.shiftl b4_1 1))) in
  sign_extend 13 raw.

Definition get_u_imm (instr : word) : word :=
  wrap_word (N.shiftl (extract_bits instr 12 31) 12).

Definition get_j_imm (instr : word) : word :=
  let b20     := N.b2n (N.testbit instr 31) in
  let b19_12  := extract_bits instr 12 19   in
  let b11     := N.b2n (N.testbit instr 20) in
  let b10_1   := extract_bits instr 21 30   in
  let raw := N.lor (N.shiftl b20 20)
            (N.lor (N.shiftl b19_12 12)
            (N.lor (N.shiftl b11 11)
                   (N.shiftl b10_1 1))) in
  sign_extend 21 raw.

(* ------------------------------------------------------------------ *)
(* Section 3 — The imm_gen specification                              *)
(* ------------------------------------------------------------------ *)

Definition imm_gen_spec (instr : word) : word :=
  match decode_opcode (instr_opcode instr) with
  | OP_OP_IMM | OP_LOAD | OP_JALR => get_i_imm instr
  | OP_STORE                       => get_s_imm instr
  | OP_BRANCH                      => get_b_imm instr
  | OP_LUI | OP_AUIPC              => get_u_imm instr
  | OP_JAL                         => get_j_imm instr
  | OP_OP | OP_INVALID             => 0
  end.

(* ------------------------------------------------------------------ *)
(* Section 4 — Correctness Proofs (Temporary Placeholders)            *)
(* ------------------------------------------------------------------ *)


Lemma instr_rd_in_range :
  forall instr : word, (instr_rd instr < REG_COUNT)%nat.
Proof.
  intro instr.
  unfold instr_rd, REG_COUNT.
  apply Nat.mod_upper_bound.
  compute. discriminate.
Qed.

Lemma instr_rs1_in_range :
  forall instr : word, (instr_rs1 instr < REG_COUNT)%nat.
Proof.
  intro instr.
  unfold instr_rs1, REG_COUNT.
  apply Nat.mod_upper_bound.
  compute. discriminate.
Qed.

Lemma instr_rs2_in_range :
  forall instr : word, (instr_rs2 instr < REG_COUNT)%nat.
Proof.
  intro instr.
  unfold instr_rs2, REG_COUNT.
  apply Nat.mod_upper_bound.
  compute. discriminate.
Qed.

