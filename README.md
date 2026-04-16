# PULSAR

> A hall-effect keyboard built end-to-end — from silicon to firmware.

No microcontroller. No debounce. No legacy constraints.

PULSAR is a keyboard designed from scratch to remove latency at every level of the stack. Instead of adapting to generic hardware, we built a **custom processing architecture** and a fully parallel sensing system tailored specifically for input speed.

**Target: sub-130μs from key movement to USB report.**

---

## Why PULSAR

Modern “fast” keyboards still rely on decades-old design patterns:

- Keys are scanned in loops  
- Debounce is handled in software  
- USB reports are rate-limited  

These are not physical limitations — they’re architectural ones.

PULSAR takes a different approach:
- Read everything in parallel  
- Eliminate debounce at the source  
- Remove unnecessary waiting between input and output  

---

## What makes it different

**Analog sensing instead of contact switches**  
Each key uses a Hall effect sensor that measures position continuously — not just on/off. This removes mechanical noise entirely and opens the door to smarter input processing.

**Full parallel acquisition**  
All keys are sampled simultaneously, not scanned in sequence. Input is captured as a snapshot, not reconstructed over time.

**Custom processing pipeline**  
The system is built around a purpose-specific architecture designed for one job: turning sensor data into input events with minimal delay.

**High-frequency USB output**  
Instead of batching inputs, reports are sent as soon as they’re ready — aligned with the fastest intervals the USB standard allows.

---

## The idea

PULSAR isn’t just a keyboard — it’s a rethinking of how input devices should work when you stop designing around general-purpose hardware.

By controlling the entire stack:
- sensing  
- processing  
- and output  

we remove layers of latency that are usually taken for granted.

---

## What you get

- **Instant actuation** (no debounce delay)  
- **Continuous key position** (not just binary input)  
- **Rapid trigger behavior** (keys re-arm dynamically)  
- **Per-key customization** (thresholds, curves, behavior)  
- **True N-key rollover by design**  

---

## Current status

PULSAR is an actively developed project combining hardware, low-level systems, and firmware into a single tightly integrated platform.

We’re iterating toward:
- fully working hardware  
- stable firmware stack  
- and verified latency measurements  

---

## Team

- Axel — architecture & low-level systems  
- Agustín — firmware & input logic  
- Emiliano — hardware & PCB design  

---

## Vision

Most keyboards are built by stacking solutions on top of constraints.

PULSAR removes the constraints first — and builds up from there.

---

## License 

MIT
