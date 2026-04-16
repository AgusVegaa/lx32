#!/usr/bin/env python3
"""
bench_summary.py — pretty-print bench_results.json as a table.

Usage:
    python3 tools/bench_summary.py [bench_results.json]

Called by `make bench-summary`.  The report file defaults to bench_results.json
in the current directory if no argument is supplied.
"""

import json
import sys
import os


def main():
    report_path = sys.argv[1] if len(sys.argv) > 1 else "bench_results.json"

    if not os.path.exists(report_path):
        print(f"No benchmark results found at '{report_path}'.")
        print("Run: make bench-all")
        sys.exit(1)

    try:
        with open(report_path) as f:
            results = json.load(f)
    except Exception as e:
        print(f"Failed to parse '{report_path}': {e}")
        sys.exit(1)

    if not results:
        print("Report is empty — no programs were benchmarked.")
        sys.exit(0)

    # ── Header ────────────────────────────────────────────────────────────────
    HDR = (
        f"{'Program':<32} {'Status':<16} {'Bytes':>6} {'S.Instr':>8}"
        f" {'Cycles':>8} {'D.Instr':>8} {'Stalls':>7} {'IPC':>7}  {'Exit':>5}"
    )
    SEP = "─" * len(HDR)

    print(f"\n=== LX32 Benchmark Results  ({report_path}) ===\n")
    print(HDR)
    print(SEP)

    # ── Per-program rows ──────────────────────────────────────────────────────
    for r in results:
        name   = r.get("program",               "?")[:31]
        status = r.get("status",                "?")[:15]
        bsz    = r.get("binary_bytes",           0)
        sinstr = r.get("static_instructions",    0)
        cyc    = r.get("cycles_total",           0)
        dinstr = r.get("instructions_committed", 0)
        stalls = r.get("stall_cycles",           0)
        ipc    = r.get("ipc",                    0.0)
        ec     = r.get("exit_code",              None)
        ec_str = str(ec) if ec is not None else "—"

        print(
            f"{name:<32} {status:<16} {bsz:>6} {sinstr:>8}"
            f" {cyc:>8} {dinstr:>8} {stalls:>7} {ipc:>7.4f}  {ec_str:>5}"
        )

    print(SEP)
    print(
        "\nColumns: S.Instr = static instruction count (binary_bytes / 4)  |"
        "  D.Instr = dynamic instructions committed  |  IPC = D.Instr / Cycles"
    )

    # ── Instruction mix breakdown ─────────────────────────────────────────────
    mix_keys = ["alu", "load", "store", "branch", "jump", "upper_imm", "custom", "other"]
    total_mix = {k: sum(r.get("instruction_mix", {}).get(k, 0) for r in results) for k in mix_keys}
    total_dyn = sum(total_mix.values())

    if total_dyn > 0:
        print("\nAggregate dynamic instruction mix:")
        for k in mix_keys:
            pct = total_mix[k] / total_dyn * 100
            bar = "█" * int(pct / 2)
            print(f"  {k:<10} {total_mix[k]:>8}  {pct:>5.1f}%  {bar}")

    # ── Aggregate performance ─────────────────────────────────────────────────
    total_cyc   = sum(r.get("cycles_total",           0) for r in results)
    total_din   = sum(r.get("instructions_committed", 0) for r in results)
    total_stall = sum(r.get("stall_cycles",           0) for r in results)
    agg_ipc     = total_din / total_cyc if total_cyc > 0 else 0.0

    print(f"\nAggregate across {len(results)} program(s):")
    print(f"  Total cycles         : {total_cyc:,}")
    print(f"  Total D. instructions: {total_din:,}")
    print(f"  Total stall cycles   : {total_stall:,}")
    print(f"  Aggregate IPC        : {agg_ipc:.4f}")
    if total_cyc > 0:
        stall_pct = total_stall / total_cyc * 100
        print(f"  Stall overhead       : {stall_pct:.2f}%")
    print()


if __name__ == "__main__":
    main()
