# LX32 ISA Formal Model (Complete Equation Sheet)

This document gives a full mathematical description of the ISA model used by LX32 and its global closure theorem. The notation and equations are aligned with the mechanized Coq semantics in `tools/lx32_formal/` and written as a single reference sheet.

## 1. State Space and Primitive Operators

The base domains are

Equation (1):

$$
\mathbb{W}=\{0,1,\dots,2^{32}-1\},\qquad
\mathbb{R}=\{0,1,\dots,31\},\qquad
\mathbb{B}=\{\mathsf{false},\mathsf{true}\}.
$$

An architectural state is

Equation (2):

$$
S=(pc,rf,mem),\quad pc\in\mathbb{W},\quad rf:\mathbb{R}\to\mathbb{W},\quad mem:\mathbb{W}\to\mathbb{W}.
$$

Word truncation is

Equation (3):

$$
\operatorname{wrap}(x)=x\bmod 2^{32}.
$$

Program-counter helpers are

Equation (4):

$$
pc\_next\_seq(pc)=\operatorname{wrap}(pc+4),
\qquad
pc\_next\_branch(pc,off)=\operatorname{wrap}(pc+off).
$$

## 2. Register and Memory Algebra

Register read with bounds guard:

Equation (5):

$$
\operatorname{rf\_read}(rf,i)=
\begin{cases}
rf(i), & i<32,\\
0, & i\ge 32.
\end{cases}
$$

Register write with hardwired $x0$:

Equation (6):

$$
\operatorname{rf\_write}(rf,a,v)(i)=
\begin{cases}
rf(i), & a=0,\\
\operatorname{wrap}(v), & a\in\mathbb{R}\setminus\{0\}\land i=a,\\
rf(i), & \text{otherwise}.
\end{cases}
$$

Memory write:

Equation (7):

$$
\operatorname{mem\_write}(mem,a,v)(x)=
\begin{cases}
\operatorname{wrap}(v), & x=a,\\
mem(x), & x\neq a.
\end{cases}
$$

## 3. Decode Equations

Bit slicing:

Equation (8):

$$
\operatorname{extract\_bits}(w,lo,hi)=\bigl(w\gg lo\bigr)\;\&\;\bigl(2^{hi-lo+1}-1\bigr).
$$

Instruction fields:

Equation (9):

$$
\begin{aligned}
opcode &= \operatorname{extract\_bits}(instr,0,6),\\
rd &= \operatorname{extract\_bits}(instr,7,11)\bmod 32,\\
rs1 &= \operatorname{extract\_bits}(instr,15,19)\bmod 32,\\
rs2 &= \operatorname{extract\_bits}(instr,20,24)\bmod 32,\\
funct3 &= \operatorname{extract\_bits}(instr,12,14),\\
funct7\_5 &= \operatorname{bit}(instr,30).
\end{aligned}
$$

Opcode-class decode:

Equation (10):

$$
\operatorname{decode\_opcode}(opcode)\in
\{OP\_LUI,OP\_AUIPC,OP\_JAL,OP\_JALR,OP\_BRANCH,OP\_LOAD,OP\_STORE,OP\_OP\_IMM,OP\_OP,OP\_INVALID\}.
$$

Immediate generation is selected by opcode class:

Equation (11):

$$
imm=\operatorname{imm\_gen\_spec}(instr)
$$

with canonical constructors $I,S,B,U,J$ as in `LX32_Decode.v`.

## 4. Control and Datapath Equations

Control decode is

Equation (12):

$$
ctrl=\operatorname{decode\_main\_control}(op,funct3,funct7\_5).
$$

Read stage:

Equation (13):

$$
rs1\_val=\operatorname{rf\_read}(rf,rs1),\qquad rs2\_val=\operatorname{rf\_read}(rf,rs2).
$$

ALU input muxes:

Equation (14):

$$
alu\_a=
\begin{cases}
pc,& op=OP\_AUIPC,\\
rs1\_val,& \text{otherwise},
\end{cases}
\qquad
alu\_b=
\begin{cases}
imm,& ctrl.alu\_src=\mathsf{true},\\
rs2\_val,& \text{otherwise}.
\end{cases}
$$

ALU semantics:

Equation (15):

$$
alu\_res=\operatorname{alu\_spec}(alu\_a,alu\_b,ctrl.alu\_ctrl).
$$

Branch decision:

Equation (16):

$$
br\_taken=\operatorname{branch\_taken\_spec}(rs1\_val,rs2\_val,ctrl.branch\_en,ctrl.branch\_op).
$$

Memory next-state:

Equation (17):

$$
mem'=
\begin{cases}
\operatorname{mem\_write}(mem,alu\_res,rs2\_val),& ctrl.mem\_write=\mathsf{true},\\
mem,& ctrl.mem\_write=\mathsf{false}.
\end{cases}
$$

Writeback selection:

Equation (18):

$$
wb=
\begin{cases}
mem'(alu\_res),& ctrl.result\_src=1,\\
pc\_next\_seq(pc),& ctrl.result\_src=2,\\
imm,& ctrl.result\_src=3,\\
alu\_res,& \text{otherwise}.
\end{cases}
$$

Register-file next-state:

Equation (19):

$$
rf'=
\begin{cases}
\operatorname{rf\_write}(rf,rd,wb),& ctrl.reg\_write=\mathsf{true},\\
rf,& ctrl.reg\_write=\mathsf{false}.
\end{cases}
$$

Program-counter update:

Equation (20):

$$
pc'=
\begin{cases}
pc\_next\_branch(pc,imm),& op=OP\_JAL,\\
\operatorname{wrap}\bigl((rs1\_val+imm)\;\&\;\texttt{0xFFFF\_FFFE}\bigr),& op=OP\_JALR,\\
pc\_next\_branch(pc,imm),& br\_taken=\mathsf{true},\\
pc\_next\_seq(pc),& \text{otherwise}.
\end{cases}
$$

Thus one ISA step is

Equation (21):

$$
\operatorname{Step}_{ISA}(S,instr)=S'=(pc',rf',mem').
$$

## 5. Trace Semantics

For any instruction trace $\tau$:

Equation (22a):

$$
\operatorname{Trace}_{ISA}(S,[])=S,
$$

Equation (22b):

$$
\operatorname{Trace}_{ISA}(S,i::\tau)=\operatorname{Trace}_{ISA}(\operatorname{Step}_{ISA}(S,i),\tau).
$$

## 6. Global ISA Closure Equation (Canonical)

The canonical closure theorem used by the repository is `T7_closure_claim_end_to_end`:

Equation (23):

$$
\begin{aligned}
\forall f,\;&rtl\_refines\_spec(f)\Rightarrow
rtl\_step\_contract(f)
\land lockstep\_cycle\_obligation(f)
\\
&\land\Bigl(\forall \tau,\;rf(\operatorname{Trace}_{RTL}(f,s_0,\tau),0)=0\Bigr)
\\
&\land\Bigl(\forall S,instr,\;state\_wf(S)\Rightarrow rf(f(S,instr),0)=0\Bigr)
\\
&\land\Bigl(\forall instr,\;\neg\bigl(ctrl\_reg\_write(instr)\land ctrl\_mem\_write(instr)\bigr)\Bigr).
\end{aligned}
$$

This is the single ISA-wide formal contract used by closure validation.

## 7. Term Glossary

$S$: architectural machine state.

$pc$: program counter component of $S$.

$rf$: register-file function component of $S$.

$mem$: memory function component of $S$.

$instr$: current instruction word.

$op$: decoded opcode class.

$imm$: immediate from `imm_gen_spec`.

$ctrl$: control record from `decode_main_control`.

$alu\_res$: ALU output from `alu_spec`.

$br\_taken$: branch decision from `branch_taken_spec`.

$rtl\_refines\_spec$: step-level RTL=ISA equality hypothesis.

$rtl\_step\_contract$: per-cycle observable agreement on $(pc,rf,mem)$.

$lockstep\_cycle\_obligation$: per-cycle lockstep-visible agreement on $(pc,rf)$.

## 8. Theorem-Proof Sketch

**Theorem (Global ISA Closure).** Under `rtl_refines_spec`, Equation (23) holds.

**Proof sketch.**
The closure is composed from mechanized lemmas in `tools/lx32_formal/LX32_Safety.v`: step refinement implies the observable contract (`rtl_refines_spec_implies_step_contract`), which implies lockstep-visible agreement (`rtl_step_contract_implies_lockstep_cycle`); trace lifting is provided by `rtl_refines_spec_lifts_to_trace`; x0 safety follows from `rtl_correct_x0_immutable` and `T6b_rtl_trace_x0_zero`; decode coherence is provided by `T3_control_coherence`. The final conjunction is exactly assembled by `T7_closure_claim_end_to_end`.

## 9. Reproducibility

```bash
make coq-clean
make coq-local
```

```bash
make closure-proof SEED=42
```


