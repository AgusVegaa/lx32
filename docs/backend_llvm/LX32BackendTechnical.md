# LX32 LLVM Backend - Technical Decisions Reference

> **State** frozen at CI build #45 of `pulsar-experiments`, commit `ca99602`.
> **Rule** update this document whenever a nre `LX32ISD::*` node is added, operand changes, a branch/call/return pattern changes, or a `lcc` crash requieres a lowering workaround.


---

## 1. Design Decisions

### 1.1 `ISD::BR_CC` and  `ISD::BRCOND` are both marked `Custom` in lowering.

**Where** `LX32ISelLowering.cpp`, contructor - two explicit `setOperationAction` calls:

```cpp
setOperationAction(ISD::BR_CC,  MVT::i32,   Custom);
setOperationAction(ISD::BRCOND, MVT::Other, Custom);
```

**Why not leave them as `Expand` or `Legal`?**
The generic DAGCombiner and instruction selector do not know about LX32's branch pseudo set (`PseudoBEQ/BNE/BLT/BGE/BLTU/BGEU`). If left the generic path, `BRCOND` woult either fail to select (crash) ot produce synthetic compare-and-branch sequence that fights with out `LX21ISD::BRCC` node. Marking both `Custom` forces every conditional branch through `LowerOperation -> LowerBR_CC / LowerBRCOND`, which produces a dingle canonical `LX32ISD::BRCC` node that the TableGen patterns in section 12 of `LX32IntrInfo.td` then match cleanly.

**What `setBooleanContents(ZeroOrOneBooleanContent)` buys us:**
DAG combines that fols `setcc` results into boolean expressions use the boolean content hint to decide whether they can skip zero-extensions. Setting it to `ZeroOrOneBoleanContent` keeps `i1` -typed result as explicit `0/1` values, which makes the BRCOND path predictable: when `lowerBRCOND` receives a condition that is not a `SETCC`, it zero-extends to `i32` and emits `cond != 0` against `XO` without ambiguity.

---

### 1.2 Canonical operand order for `LX32USD::BRCC`

**Order:** `chain, lhs, rhs, condcode, target`

**Where it is set:** `lowerBR_CC` in `LX32ISelLowering.cpp`:

```cpp
return DAG.getNode(LX32ISD::BRCC, DL, MVT::Other,
                    Op,getOperand(0),       // chain 
                    Op0,                    // lhs (after normalization and possible swap)
                    Op1,                    // rhs
                    DAG.getCondCode(CC),
                    Target);
```

**Where it is consumed:** `LX32ISelDAGToDAG` and the `LX32BccPat` multiclass in Section 12 of `LX32InstrInfo.td`:

```tablegen
multiclass LX32BccPat<CondCode Cond, Instruction Inst> {
    def : Pat<(LX32brcc (i32 GPR:$rs1), GPR:$rs2, Cond, bb:$target), ...>;
    def : Pat<(LX32brcc (i32 GPR:$rs1), 0, Cond, bb:$target), ...>;
}
```

The TableGen `SDT_LX32BrCC` type profile encodes this contract:

```tablegen
defSDT_LX32BrCC : SDTypeProfile<0, 4, [SDTCisSameAs<0, 1>,  // lhs/rhs same type
                                        SDTCisVT<2, OtherVT>, // condcode
                                        SDTCisVT<3, OtherVT>]>; // target bb
```

**Why this matters:** if `lowerBR_CC` and the `LX32BccPat` patterns ever disagree on operand order, the selector silently selects the wrong registers or produces a crash in a late pass. The operand order is a load-bearing contract - do not change it without updating both sides simultaneusly.

---
### 1.3 Condition code normalization: the eight-to-six reduction

LX32's branch instructions implement six condition: `BEQ, BNE, BLT, BGE, BLTU, BGEU`. LLVM's `ISD:CondCode` has more variants. `LowerBR_CC` reduces them in the switch inside `LowerBR_CC`:

```cpp
case ISD::SETGT: CC = ISD::SETLT; Swap = true; break; // a > b -> b < a
case ISD::SETLE: CC = ISD::SETGE; Swap = true; break; // a <= b -> b >= a
case ISD::SETUGT: CC = ISD::SETULT; Swap = true; break;
case ISD::SETULE: CC = ISD::SETUGE; Swap = true; break;
```

When `Swap = true`, `lhs` and `rhs` are exchanged before building the `LX32ISD::BRCC` node. This keeps the `LX32BccPat` multiclass small (6 entries, one per hardware condition) and avoids duplicating patterns for the mirror conditions.

**Unsupported codes** (`SETOEQ`, `SETUNE`, etc.) hit `report_fatal_error`. These are floating-point condition codes; since LX32 has no FPU they should never appear in valid IR targeting this backend. If they do appear, the error message is the right behavior - it surfaces the problem immediately rather silently miscompiling.

---
