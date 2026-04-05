(* ================================================================== *)
(* LX32_Arch.v                                                        *)
(* Foundational types and architectural state for the LX32 processor. *)
(*                                                                    *)
(* Corresponds to: lx32_arch_pkg.sv                                   *)
(*                                                                    *)
(* This file defines:                                                 *)
(*   - The word type (32-bit unsigned integers via the BinNat library)*)
(*   - The register file model (a function from index to word)        *)
(*   - The memory model (a function from address to word)             *)
(*   - The full architectural state (MachineState)                    *)
(*   - The zero-register invariant                                    *)
(*                                                                    *)
(* Design note: We model words as Coq's N (non-negative integers)    *)
(* bounded to 2^32, rather than Z (signed integers), because the     *)
(* hardware register file is inherently unsigned bitwise storage.     *)
(* Signed semantics are applied per-operation (SLT, SRA, branches)   *)
(* by interpreting the stored bits at the use site.                   *)
(* ================================================================== *)

Require Import Coq.Arith.Arith.
Require Import Coq.NArith.NArith.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Import ListNotations.

(* ------------------------------------------------------------------ *)
(* Section 0 — Fundamental constants                                  *)
(*                                                                    *)
(* These mirror lx32_arch_pkg.sv's parameters exactly.               *)
(* XLEN = 32, REG_COUNT = 32, PC_WIDTH = 32.                         *)
(* ------------------------------------------------------------------ *)

Definition XLEN : nat := 32.
Definition REG_COUNT : nat := 32.

(* The modulus for 32-bit word arithmetic: 2^32 *)
Definition word_modulus : N := 2^32.

(* ------------------------------------------------------------------ *)
(* Section 1 — Word type                                              *)
(*                                                                    *)
(* A word is any N in the range [0, 2^32).                            *)
(* We define a predicate rather than a dependent type for simplicity; *)
(* lemmas about word operations take this as a hypothesis.            *)
(* ------------------------------------------------------------------ *)

(* A 32-bit word value — any N is valid; wrap_word enforces the range *)
Definition word := N.

(* Wrap an arbitrary N into [0, 2^32) by taking mod 2^32.            *)
(* This models the hardware's implicit truncation on every operation. *)
Definition wrap_word (n : N) : word := N.modulo n word_modulus.

(* A word is in range if it is strictly less than 2^32 *)
Definition word_in_range (w : word) : Prop := (w < word_modulus)%N.

Lemma wrap_word_in_range : forall n, word_in_range (wrap_word n).
Proof.
  intro n. unfold word_in_range, wrap_word.
  apply N.mod_lt. unfold word_modulus. compute. discriminate.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 2 — Register file model                                    *)
(*                                                                    *)
(* The register file is modeled as a total function                   *)
(*   reg_file : nat -> word                                           *)
(* where the argument is the register index (0-31).                   *)
(*                                                                    *)
(* The x0 invariant: reg_file 0 = 0 always.                          *)
(* This matches register_file.sv: "assign regs_out[0] = 32'h0"       *)
(* ------------------------------------------------------------------ *)

Definition reg_file := nat -> word.

(* A register file satisfies the x0-hardwired-zero invariant *)
Definition rf_wf (rf : reg_file) : Prop := rf 0 = 0%N.

(* Read a register with bounds check: returns 0 for index >= 32      *)
(* (hardware also constrains indices to 5 bits = 0..31)              *)
Definition rf_read (rf : reg_file) (idx : nat) : word :=
  if Nat.ltb idx REG_COUNT then rf idx else 0%N.

(* Write a register, enforcing the x0 invariant.                     *)
(* If addr = 0, the write is silently discarded (hardware behavior).  *)
(* This models the one-hot write decoder in register_file.sv:         *)
(*   assign write_en = (we && (addr_rd != 5'd0)) ? ... : 32'b0;      *)
Definition rf_write (rf : reg_file) (addr : nat) (val : word) : reg_file :=
  if Nat.eqb addr 0 then rf
  else if Nat.ltb addr REG_COUNT
       then fun i => if Nat.eqb i addr then wrap_word val else rf i
       else rf.

(* Writing to x0 preserves the invariant *)
Lemma rf_write_x0_preserved :
  forall rf val, rf_wf rf -> rf_wf (rf_write rf 0 val).
Proof.
  intros rf val Hwf.
  unfold rf_write, rf_wf. simpl. exact Hwf.
Qed.

(* Writing to any non-x0 register preserves the invariant *)
Lemma rf_write_nonzero_wf :
  forall rf addr val,
    rf_wf rf ->
    addr <> 0 ->
    rf_wf (rf_write rf addr val).
Proof.
  intros rf addr val Hwf Hne.
  destruct addr as [|addr'].
  - contradiction.
  - unfold rf_wf, rf_write. simpl.
    destruct (Nat.ltb (S addr') REG_COUNT); simpl; exact Hwf.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 3 — Memory model                                           *)
(*                                                                    *)
(* Memory is modeled as a total function from address to word.        *)
(* The address space is the full 32-bit range.                        *)
(*                                                                    *)
(* Note: lx32_system.sv exposes a memory interface (mem_addr,        *)
(* mem_rdata, mem_wdata, mem_we) without specifying alignment or      *)
(* sub-word granularity. This model assumes word-aligned 32-bit       *)
(* accesses, which is consistent with the single-cycle design.        *)
(* ------------------------------------------------------------------ *)

Definition memory := word -> word.

(* Write a word to memory at the given address *)
Definition mem_write (mem : memory) (addr val : word) : memory :=
  fun a => if N.eqb a addr then wrap_word val else mem a.

(* ------------------------------------------------------------------ *)
(* Section 4 — The architectural state (MachineState)                 *)
(*                                                                    *)
(* The complete observable state of the LX32 processor at any cycle   *)
(* boundary consists of exactly three components:                     *)
(*   1. pc  — the program counter (32 bits)                           *)
(*   2. rf  — the register file (32 × 32-bit values)                  *)
(*   3. mem — the data memory (2^32 × 32-bit values)                  *)
(*                                                                    *)
(* This state model is the formal foundation for all subsequent       *)
(* specifications. The step relation in LX32_Step.v defines how       *)
(* executing one instruction transforms one MachineState into another.*)
(* ------------------------------------------------------------------ *)

Record MachineState : Type := mkState {
  pc  : word;      (* Program counter: address of current instruction *)
  rf  : reg_file;  (* Register file: 32 general-purpose 32-bit regs  *)
  mem : memory;    (* Data memory: 32-bit addressable word storage     *)
}.

(* Well-formedness of a machine state: the x0 invariant must hold     *)
Definition state_wf (s : MachineState) : Prop := rf_wf (rf s).

(* The initial state after reset: PC=0, all registers=0, memory=0   *)
(* Corresponds to: always_ff @(posedge clk or posedge rst) if (rst) pc <= 0 *)
Definition initial_state : MachineState := mkState
  0%N                    (* pc = 0 *)
  (fun _ => 0%N)         (* all registers = 0 *)
  (fun _ => 0%N).        (* all memory = 0 *)

(* The initial state is well-formed *)
Lemma initial_state_wf : state_wf initial_state.
Proof.
  unfold state_wf, rf_wf, initial_state. reflexivity.
Qed.

(* ------------------------------------------------------------------ *)
(* Section 5 — PC arithmetic                                          *)
(*                                                                    *)
(* The PC is incremented by 4 for sequential instructions or set to   *)
(* PC + offset for taken branches. Both wrap at 2^32.                 *)
(* Corresponds to: assign next_pc = ... ? (pc + imm_ext) : (pc + 4)  *)
(* ------------------------------------------------------------------ *)

Definition pc_next_seq (current_pc : word) : word :=
  wrap_word (N.add current_pc 4%N).

Definition pc_next_branch (current_pc offset : word) : word :=
  wrap_word (N.add current_pc offset).

(* Signed extension: interpret a word as a signed value for branch    *)
(* offset arithmetic. Needed for negative (backwards) branches.       *)
(* A word w is negative (as signed) if its bit 31 is set.             *)
Definition sign_bit (w : word) : bool :=
  N.testbit w 31.

(* Sign-extend a 32-bit word to a Z for signed arithmetic             *)
Definition word_to_signed (w : word) : Z :=
  if sign_bit w
  then Z.sub (Z.of_N w) (Z.of_N word_modulus)
  else Z.of_N w.

