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

    // LX.SENSOR x2, x1
    let lx_sensor = enc_custom_i(0b000, 1, 2, 0x0b);
    unsafe { tick_core(tb.rtl, 0, lx_sensor, 0) };
    tb.gold.step(lx_sensor, 0, false);
    let rtl_x2 = unsafe { get_reg(tb.rtl, 2) };
    let gold_x2 = tb.gold.reg_file.read_rs1(2);
    assert_eq!(rtl_x2, 1005);
    assert_eq!(rtl_x2, gold_x2);

    // LX.DELTA x3, x1
    let lx_delta = enc_custom_i(0b010, 1, 3, 0x0b);
    unsafe { tick_core(tb.rtl, 0, lx_delta, 0) };
    tb.gold.step(lx_delta, 0, false);
    let rtl_x3 = unsafe { get_reg(tb.rtl, 3) };
    let gold_x3 = tb.gold.reg_file.read_rs1(3);
    assert_eq!(rtl_x3, 20);
    assert_eq!(rtl_x3, gold_x3);

    // x4 = 0x0f, LX.CHORD x5, x4 (match expected)
    let addi_x4_0f = enc_addi(4, 0, 0x00f);
    unsafe { tick_core(tb.rtl, 0, addi_x4_0f, 0) };
    tb.gold.step(addi_x4_0f, 0, false);

    let lx_chord = enc_custom_i(0b011, 4, 5, 0x0b);
    unsafe { tick_core(tb.rtl, 0, lx_chord, 0) };
    tb.gold.step(lx_chord, 0, false);
    let rtl_x5 = unsafe { get_reg(tb.rtl, 5) };
    let gold_x5 = tb.gold.reg_file.read_rs1(5);
    assert_eq!(rtl_x5, 1);
    assert_eq!(rtl_x5, gold_x5);
}

#[test]
fn test_custom1_wait_and_report_matches_golden() {
    let mut tb = TestBench::new();

    // x1 = 3, then LX.WAIT x1
    let addi_x1_3 = enc_addi(1, 0, 3);
    unsafe { tick_core(tb.rtl, 0, addi_x1_3, 0) };
    tb.gold.step(addi_x1_3, 0, false);

    let pre_pc_rtl = unsafe { get_pc(tb.rtl) };
    let pre_pc_gold = tb.gold.pc;
    assert_eq!(pre_pc_rtl, pre_pc_gold);

    let lx_wait = enc_custom_i(0b000, 1, 0, 0x2b);
    unsafe { tick_core(tb.rtl, 0, lx_wait, 0) };
    tb.gold.step(lx_wait, 0, false);
    let issue_pc_rtl = unsafe { get_pc(tb.rtl) };
    let issue_pc_gold = tb.gold.pc;
    assert_eq!(issue_pc_rtl, pre_pc_rtl);
    assert_eq!(issue_pc_rtl, issue_pc_gold);

    // WAIT must hold for at least 3 cycles.
    for _ in 0..3 {
        let nop = 0x0000_0013u32;
        unsafe { tick_core(tb.rtl, 0, nop, 0) };
        tb.gold.step(nop, 0, false);
        assert_eq!(unsafe { get_pc(tb.rtl) }, tb.gold.pc);
        assert_eq!(unsafe { get_pc(tb.rtl) }, issue_pc_rtl);
    }

    // Then it must resume within a bounded window.
    let mut resumed = false;
    for _ in 0..4 {
        let nop = 0x0000_0013u32;
        unsafe { tick_core(tb.rtl, 0, nop, 0) };
        tb.gold.step(nop, 0, false);
        let pc_rtl = unsafe { get_pc(tb.rtl) };
        assert_eq!(pc_rtl, tb.gold.pc);
        if pc_rtl == issue_pc_rtl + 4 {
            resumed = true;
            break;
        }
    }
    assert!(resumed, "WAIT did not release within expected bound");

    // REPORT should not write registers and should keep models aligned.
    let addi_x6 = enc_addi(6, 0, 0x123);
    unsafe { tick_core(tb.rtl, 0, addi_x6, 0) };
    tb.gold.step(addi_x6, 0, false);
    let x7_before = unsafe { get_reg(tb.rtl, 7) };

    let lx_report = enc_custom_i(0b001, 6, 0, 0x2b);
    unsafe { tick_core(tb.rtl, 0, lx_report, 0) };
    tb.gold.step(lx_report, 0, false);

    let x7_after_rtl = unsafe { get_reg(tb.rtl, 7) };
    let x7_after_gold = tb.gold.reg_file.read_rs1(7);
    assert_eq!(x7_before, x7_after_rtl);
    assert_eq!(x7_after_rtl, x7_after_gold);
    assert_eq!(unsafe { get_pc(tb.rtl) }, tb.gold.pc);
}



