(* ================================================================== *)
(* LX32_Control.v                                                     *)
(* Formal specification of the LX32 control unit.                     *)
(*                                                                    *)
(* Corresponds to: core/control_unit.sv                               *)
(*                                                                    *)
(* This file defines:                                                  *)
(*   - Structured control-signal records                               *)
(*   - Main decode and ALU-control decode functions                    *)
(*   - Local safety lemmas for decode consistency                      *)
(* ================================================================== *)

Require Import Coq.Bool.Bool.
Require Import Coq.NArith.NArith.

(* Shared architectural, ALU, branch, and decode specifications. *)
Require Import LX32_Arch.
Require Import LX32_ALU.
Require Import LX32_Branch.
Require Import LX32_Decode.

(* ------------------------------------------------------------------ *)
(* Section 0 — Control signal record                                  *)
(* ------------------------------------------------------------------ *)

Record control_signals : Type := mkCtrl {
  ctrl_reg_write  : bool;
  ctrl_alu_src    : bool;
  ctrl_mem_write  : bool; (* Prefixed to avoid namespace collisions. *)
  ctrl_result_src : N;
  ctrl_branch_en  : bool;
  ctrl_branch_op  : branch_op;
  ctrl_alu_ctrl   : alu_op;
}.

(* ------------------------------------------------------------------ *)
(* Section 1 — ALU control decode                                     *)
(* ------------------------------------------------------------------ *)

Inductive alu_main : Type :=
  | ALU_MAIN_ADD
  | ALU_MAIN_SUB
  | ALU_MAIN_FUNC.

Definition decode_alu_control
    (main : alu_main)
    (op : opcode)
    (funct3 : N)
    (funct7_5 : bool) : alu_op :=
  match main with
  | ALU_MAIN_ADD  => ALU_ADD
  | ALU_MAIN_SUB  => ALU_SUB
  | ALU_MAIN_FUNC =>
      match funct3 with
      | 0%N => if andb (match op with OP_OP => true | _ => false end) funct7_5
             then ALU_SUB else ALU_ADD
      | 1%N => ALU_SLL
      | 2%N => ALU_SLT
      | 3%N => ALU_SLTU
      | 4%N => ALU_XOR
      | 5%N => if funct7_5 then ALU_SRA else ALU_SRL
      | 6%N => ALU_OR
      | 7%N => ALU_AND
      | _ => ALU_ADD
      end
  end.

(* ------------------------------------------------------------------ *)
(* Section 2 — Main control decode                                    *)
(* ------------------------------------------------------------------ *)

Definition decode_main_control
    (op : opcode)
    (funct3 : N)
    (funct7_5 : bool) : control_signals :=
  match op with
  (* Load: reg_write=T, alu_src=T (imm), mem_write=F, result_src=1 (mem) *)
  | OP_LOAD => mkCtrl
      true true false 1%N false BR_EQ ALU_ADD

  (* Store: reg_write=F, alu_src=T (imm), mem_write=T, result_src=0 *)
  | OP_STORE => mkCtrl
      false true true 0%N false BR_EQ ALU_ADD

  | OP_OP => mkCtrl
      true false false 0%N false BR_EQ
      (decode_alu_control ALU_MAIN_FUNC op funct3 funct7_5)

  | OP_OP_IMM => mkCtrl
      true true false 0%N false BR_EQ
      (decode_alu_control ALU_MAIN_FUNC op funct3 funct7_5)

  | OP_BRANCH =>
      let bop := match funct3 with
                 | 0%N => BR_EQ  | 1%N => BR_NE
                 | 4%N => BR_LT  | 5%N => BR_GE
                 | 6%N => BR_LTU | 7%N => BR_GEU
                 | _ => BR_EQ
                 end in
      mkCtrl false false false 0%N true bop ALU_SUB

  | OP_LUI => mkCtrl
      true true false 3%N false BR_EQ ALU_ADD

  | OP_AUIPC => mkCtrl
      true true false 0%N false BR_EQ ALU_ADD

  | OP_JAL => mkCtrl
      true true false 2%N true BR_EQ ALU_ADD

  | OP_JALR => mkCtrl
      true true false 2%N true BR_EQ ALU_ADD

  | _ => mkCtrl false false false 0%N false BR_EQ ALU_ADD
  end.

(* ------------------------------------------------------------------ *)
(* Section 3 — Safety Properties                                       *)
(* ------------------------------------------------------------------ *)

Lemma store_never_regwrite :
  forall f3 f7b, ctrl_reg_write (decode_main_control OP_STORE f3 f7b) = false.
Proof. intros. reflexivity. Qed.

Lemma branch_never_memwrite :
  forall f3 f7b, ctrl_mem_write (decode_main_control OP_BRANCH f3 f7b) = false.
Proof. intros. reflexivity. Qed.

Lemma regwrite_and_memwrite_exclusive :
  forall op f3 f7b,
    let ctrl := decode_main_control op f3 f7b in
    andb (ctrl_reg_write ctrl) (ctrl_mem_write ctrl) = false.
Proof. intros. destruct op; simpl; reflexivity. Qed.

(* ------------------------------------------------------------------ *)
(* Section 4 — Configuration specs                                    *)
(* ------------------------------------------------------------------ *)

Definition is_load_config (ctrl : control_signals) : Prop :=
  ctrl_reg_write ctrl = true /\
  ctrl_alu_src ctrl = true /\
  ctrl_mem_write ctrl = false /\
  ctrl_result_src ctrl = 1%N.

Lemma load_opcode_produces_load_config :
  forall f3 f7b, is_load_config (decode_main_control OP_LOAD f3 f7b).
Proof. intros. repeat split; reflexivity. Qed.
