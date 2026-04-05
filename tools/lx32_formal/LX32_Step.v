(* ================================================================== *)
(* LX32_Step.v                                                        *)
(* Single-instruction and trace-level execution semantics for LX32.   *)
(*                                                                    *)
(* Corresponds to: core/lx32_system.sv (integrated datapath behavior) *)
(*                                                                    *)
(* This file defines:                                                  *)
(*   - The executable architectural step function                       *)
(*   - Local invariants preserved by one-step execution                *)
(*   - Trace execution and trace-level well-formedness                 *)
(* ================================================================== *)

Require Import Coq.NArith.NArith.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.

(* Static module imports managed by Coq's dependency graph. *)
Require Import LX32_Arch.
Require Import LX32_ALU.
Require Import LX32_Branch.
Require Import LX32_Decode.
Require Import LX32_Control.

(* Ensure `_CoqProject` contains `-Q . ""` if logical paths fail. *)

(* ------------------------------------------------------------------ *)
(* Section 0 — Instruction execution                                  *)
(* ------------------------------------------------------------------ *)

Definition exec_instr (s : MachineState) (instr : word) : MachineState :=
  let op     := decode_opcode (instr_opcode instr) in
  let rs1    := instr_rs1 instr in
  let rs2    := instr_rs2 instr in
  let rd     := instr_rd  instr in
  let f3     := instr_funct3  instr in
  let f7_5   := instr_funct7_5 instr in

  let ctrl := decode_main_control op f3 f7_5 in

  let rs1_val := rf_read (rf s) rs1 in
  let rs2_val := rf_read (rf s) rs2 in

  let imm := imm_gen_spec instr in

  let is_auipc := match op with OP_AUIPC => true | _ => false end in
  let is_jal   := match op with OP_JAL   => true | _ => false end in
  let is_jalr  := match op with OP_JALR  => true | _ => false end in

  let alu_a   := if is_auipc then pc s else rs1_val in
  let alu_b   := if ctrl_alu_src ctrl then imm else rs2_val in
  let alu_res := alu_spec alu_a alu_b (ctrl_alu_ctrl ctrl) in

  let br_taken := branch_taken_spec rs1_val rs2_val
                    (ctrl_branch_en ctrl) (ctrl_branch_op ctrl) in

  let mem_after :=
    if ctrl_mem_write ctrl
    then (fun addr => if N.eqb addr alu_res then wrap_word rs2_val else mem s addr)
    else mem s in

  let load_data :=
    if N.eqb (ctrl_result_src ctrl) 1%N
    then mem_after alu_res
    else if N.eqb (ctrl_result_src ctrl) 2%N
         then pc_next_seq (pc s)
         else if N.eqb (ctrl_result_src ctrl) 3%N
              then imm
              else alu_res in

  let rf_after :=
    if ctrl_reg_write ctrl
    then rf_write (rf s) rd load_data
    else rf s in

  let next_pc :=
    if is_jal
    then pc_next_branch (pc s) imm
    else if is_jalr
         then wrap_word (N.land (N.add rs1_val imm) 4294967294%N)
         else if br_taken
              then pc_next_branch (pc s) imm
              else pc_next_seq (pc s) in

  mkState next_pc rf_after mem_after.

(* ------------------------------------------------------------------ *)
(* Section 1 — Well-formedness preservation                           *)
(* ------------------------------------------------------------------ *)

Theorem exec_preserves_wf :
  forall s : MachineState, forall instr : word,
    state_wf s -> state_wf (exec_instr s instr).
Proof.
  intros s instr Hwf.
  unfold state_wf, exec_instr.
  destruct (ctrl_reg_write (decode_main_control
                         (decode_opcode (instr_opcode instr))
                         (instr_funct3 instr)
                         (instr_funct7_5 instr))) eqn:Hrw.
  - destruct (Nat.eqb (instr_rd instr) 0) eqn:H0.
    + apply Nat.eqb_eq in H0. rewrite H0.
      apply rf_write_x0_preserved. exact Hwf.
    + apply Nat.eqb_neq in H0.
      apply rf_write_nonzero_wf.
      * exact Hwf.
      * exact H0.
  - exact Hwf.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 2 — x0 is never written                                    *)
(* ------------------------------------------------------------------ *)

Theorem x0_always_zero :
  forall s : MachineState, forall instr : word,
    state_wf s ->
    rf (exec_instr s instr) 0 = 0%N.
Proof.
  intros s instr Hwf.
  apply exec_preserves_wf. exact Hwf.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 3 — Memory modification only by STORE                      *)
(* ------------------------------------------------------------------ *)

Theorem non_store_preserves_memory :
  forall s : MachineState, forall instr : word,
    (if match decode_opcode (instr_opcode instr) with
        | OP_STORE => true
        | _ => false
        end
     then false else true) = true ->
    mem (exec_instr s instr) = mem s.
Proof.
  intros s instr Hnot_store.
  remember (decode_opcode (instr_opcode instr)) as op eqn:Hop.
  unfold exec_instr.
  cbn.
  rewrite <- Hop.
  assert (ctrl_mem_write (decode_main_control op
                       (instr_funct3 instr)
                       (instr_funct7_5 instr)) = false) as Hmw.
  {
    destruct op; try reflexivity.
    (* In the OP_STORE case, the precondition simplifies to false = true. *)
    simpl in Hnot_store. discriminate Hnot_store.
  }
  rewrite Hmw. reflexivity.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 4 — PC advances correctly                                  *)
(* ------------------------------------------------------------------ *)

Theorem sequential_pc_advance :
  forall s : MachineState, forall instr : word,
    ctrl_branch_en (decode_main_control
                  (decode_opcode (instr_opcode instr))
                  (instr_funct3 instr)
                  (instr_funct7_5 instr)) = false ->
    decode_opcode (instr_opcode instr) <> OP_JAL ->
    decode_opcode (instr_opcode instr) <> OP_JALR ->
    pc (exec_instr s instr) = pc_next_seq (pc s).
Proof.
  intros s instr Hno_branch Hnoj Hnojr.
  unfold exec_instr.
  remember (decode_opcode (instr_opcode instr)) as op eqn:Hop.
  destruct op; simpl in *; try reflexivity.
  - exfalso. exact (Hnoj eq_refl).
  - exfalso. exact (Hnojr eq_refl).
  - exfalso. discriminate Hno_branch.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 5 — Register file update correctness                       *)
(* ------------------------------------------------------------------ *)

Theorem regfile_nonrd_unchanged :
  forall s : MachineState, forall instr : word,
    forall i : nat,
      i <> instr_rd instr ->
      rf (exec_instr s instr) i = rf s i.
Proof.
  intros s instr i Hne.
  unfold exec_instr.
  destruct (ctrl_reg_write _) eqn:Hrw.
  - unfold rf_write.
    destruct (Nat.eqb (instr_rd instr) 0); simpl.
    + reflexivity.
    + destruct (Nat.ltb (instr_rd instr) REG_COUNT); simpl.
      * destruct (Nat.eqb i (instr_rd instr)) eqn:Heq.
        { apply Nat.eqb_eq in Heq. contradiction. }
        { reflexivity. }
      * reflexivity.
  - reflexivity.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 6 — Multi-step execution                                   *)
(* ------------------------------------------------------------------ *)

Require Import Coq.Lists.List.
Import ListNotations.

Fixpoint exec_trace (s : MachineState) (trace : list word) : MachineState :=
  match trace with
  | []          => s
  | instr :: rest => exec_trace (exec_instr s instr) rest
  end.

Theorem exec_trace_preserves_wf :
  forall trace : list word, forall s : MachineState,
    state_wf s -> state_wf (exec_trace s trace).
Proof.
  induction trace as [| instr rest IH].
  - intros s Hwf. exact Hwf.
  - intros s Hwf. apply IH. apply exec_preserves_wf. exact Hwf.
Qed.
