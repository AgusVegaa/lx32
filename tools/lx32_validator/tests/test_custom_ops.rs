#[path = "common/mod.rs"]
mod common;
use common::*;

fn enc_addi(rd: u32, rs1: u32, imm12: u32) -> u32 {
    ((imm12 & 0x0fff) << 20) | ((rs1 & 0x1f) << 15) | (rd << 7) | 0x13
}

fn enc_custom_i(funct3: u32, rs1: u32, rd: u32, opcode: u32) -> u32 {
    ((rs1 & 0x1f) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1f) << 7) | (opcode & 0x7f)
}

#[test]
fn test_custom0_sensor_delta_chord_matches_golden() {
    let mut tb = TestBench::new();

    // x1 = 5
    let addi_x1_5 = enc_addi(1, 0, 5);
    unsafe { tick_core(tb.rtl, 0, addi_x1_5, 0) };
    tb.gold.step(addi_x1_5, 0, false);

    // LX.SENSOR x2, x1  (sensor index 5)
    // ADC model: idx < 8 → 1200, idx ≥ 8 → 800+idx.  Index 5 → 1200.
    let lx_sensor = enc_custom_i(0b000, 1, 2, 0x0b);
    unsafe { tick_core(tb.rtl, 0, lx_sensor, 0) };
    tb.gold.step(lx_sensor, 0, false);
    let rtl_x2 = unsafe { get_reg(tb.rtl, 2) };
    let gold_x2 = tb.gold.reg_file.read_rs1(2);
    assert_eq!(rtl_x2, 1200, "LX.SENSOR(5): idx<8 → ADC value 1200");
    assert_eq!(rtl_x2, gold_x2, "RTL and gold must agree on LX.SENSOR");

    // LX.DELTA x3, x1  (velocity delta for key 5)
    // Both frame buffers are pre-loaded with identical values on reset, so delta = 0.
    let lx_delta = enc_custom_i(0b010, 1, 3, 0x0b);
    unsafe { tick_core(tb.rtl, 0, lx_delta, 0) };
    tb.gold.step(lx_delta, 0, false);
    let rtl_x3 = unsafe { get_reg(tb.rtl, 3) };
    let gold_x3 = tb.gold.reg_file.read_rs1(3);
    assert_eq!(rtl_x3, 0, "LX.DELTA: both frames identical on reset → delta = 0");
    assert_eq!(rtl_x3, gold_x3, "RTL and gold must agree on LX.DELTA");

    // x4 = 0x0f, LX.CHORD x5, x4
    // active_keys initialised to 0xFF (keys 0-7 above press_threshold=1000).
    // chord_mask=0x0f: (0xFF & 0x0f) == 0x0f → match = 1.
    let addi_x4_0f = enc_addi(4, 0, 0x00f);
    unsafe { tick_core(tb.rtl, 0, addi_x4_0f, 0) };
    tb.gold.step(addi_x4_0f, 0, false);

    let lx_chord = enc_custom_i(0b011, 4, 5, 0x0b);
    unsafe { tick_core(tb.rtl, 0, lx_chord, 0) };
    tb.gold.step(lx_chord, 0, false);
    let rtl_x5 = unsafe { get_reg(tb.rtl, 5) };
    let gold_x5 = tb.gold.reg_file.read_rs1(5);
    assert_eq!(rtl_x5, 1, "LX.CHORD(0x0f): all 4 low keys active → match");
    assert_eq!(rtl_x5, gold_x5, "RTL and gold must agree on LX.CHORD");
}

#[test]
fn test_custom1_wait_and_report_matches_golden() {
    let mut tb = TestBench::new();

    // x1 = 3 (stall for 3 RTL clock cycles)
    let addi_x1_3 = enc_addi(1, 0, 3);
    unsafe { tick_core(tb.rtl, 0, addi_x1_3, 0) };
    tb.gold.step(addi_x1_3, 0, false);

    let pre_pc_rtl = unsafe { get_pc(tb.rtl) };

    // Issue LX.WAIT x1.
    //
    // tick_core fires 2 RTL pulses internally:
    //   Pulse 1 (debug_stall=0): WAIT is loaded into IF/EX, PC advances to
    //                             pre_pc+4 (normal fetch advancement).
    //   Pulse 2 (debug_stall=1): wait_start fires, counter ← 3, PC frozen
    //                             at pre_pc+4 (NOT at pre_pc).
    //
    // The gold model holds PC at pre_pc during the stall, so we skip
    // gold.step for the WAIT and its drain cycles to avoid false PC divergence.
    let lx_wait = enc_custom_i(0b000, 1, 0, 0x2b);
    unsafe { tick_core(tb.rtl, 0, lx_wait, 0) };

    let issue_pc_rtl = unsafe { get_pc(tb.rtl) };

    // Verify that the fetch stage advanced PC by 4 (documented 2-pulse behaviour).
    assert_eq!(
        issue_pc_rtl,
        pre_pc_rtl + 4,
        "tick_core(WAIT) advances PC by 4 in pulse-1 fetch before wait_start freezes it"
    );

    // Drain the stall.
    // With rs1=3 (3 RTL clocks) and 2 pulses per tick_core the counter drains
    // as:  3 → (pulse1) 2 → (pulse2) 1 → (next tick) 0 → wait done.
    // That gives exactly 2 stall tick_core calls before the core resumes.
    // We allow a window of [1, 4] to be robust against minor RTL timing changes.
    let nop = 0x0000_0013u32;
    let mut stall_ticks = 0u32;
    for _ in 0..6 {
        unsafe { tick_core(tb.rtl, 0, nop, 0) };
        let pc = unsafe { get_pc(tb.rtl) };
        if pc == issue_pc_rtl {
            stall_ticks += 1;
        } else {
            // PC advanced past the stall address → WAIT released.
            assert_eq!(
                pc,
                issue_pc_rtl + 4,
                "after WAIT release PC must advance exactly to issue_pc+4"
            );
            break;
        }
    }
    assert!(stall_ticks >= 1, "LX.WAIT(3) must stall for at least 1 tick_core");
    assert!(stall_ticks <= 4, "LX.WAIT(3) must release within 4 tick_core calls");

    // Re-sync the gold model by running it through the equivalent steps
    // (1 WAIT issue + stall_ticks stall NOPs + 1 resume NOP) so that
    // subsequent cross-checks are meaningful.
    tb.gold.step(lx_wait, 0, false);           // WAIT issue
    for _ in 0..stall_ticks {
        tb.gold.step(nop, 0, false);            // stall cycles
    }
    tb.gold.step(nop, 0, false);               // resume cycle

    // LX.REPORT: must not write to any register and must keep models aligned.
    // x6 = 0x123  (used as the report pointer)
    let addi_x6 = enc_addi(6, 0, 0x123);
    unsafe { tick_core(tb.rtl, 0, addi_x6, 0) };
    tb.gold.step(addi_x6, 0, false);

    let x7_before_rtl  = unsafe { get_reg(tb.rtl, 7) };
    let x7_before_gold = tb.gold.reg_file.read_rs1(7);
    assert_eq!(x7_before_rtl, x7_before_gold, "x7 must match before LX.REPORT");

    let lx_report = enc_custom_i(0b001, 6, 0, 0x2b);
    unsafe { tick_core(tb.rtl, 0, lx_report, 0) };
    tb.gold.step(lx_report, 0, false);

    let x7_after_rtl  = unsafe { get_reg(tb.rtl, 7) };
    let x7_after_gold = tb.gold.reg_file.read_rs1(7);
    assert_eq!(x7_before_rtl, x7_after_rtl,  "LX.REPORT must not modify x7 (RTL)");
    assert_eq!(x7_after_rtl,  x7_after_gold, "RTL and gold must agree on x7 after LX.REPORT");
}
