# LX32K System Architecture Overview

This document provides a high-level overview of the PULSAR keyboard's system architecture, centered around the custom LX32K processor. Its purpose is to give all team members a common understanding of how the major components interact to achieve the project's primary goal: **sub-130μs latency from key movement to USB report.**

## 1. Core Philosophy: Latency is the Enemy

Every architectural decision in PULSAR is driven by the need to eliminate latency. Unlike traditional designs that rely on generic microcontrollers and sequential processing, PULSAR is a fully parallel, purpose-built system. We achieve this by:

1.  **Parallel Sensing:** All 64 Hall effect sensors are sampled simultaneously. There is no matrix scanning.
2.  **Hardware-Accelerated Processing:** Common tasks (like calculating key velocity or checking for chords) are implemented as single-cycle custom instructions in the LX32K core, not as software loops.
3.  **DMA-driven I/O:** The CPU offloads the final USB report submission to a dedicated DMA controller, allowing it to process the next frame of input without waiting.
4.  **Tightly Coupled Components:** The processor, sensor controller, and peripherals are part of a single System-on-a-Chip (SoC) design, eliminating off-chip communication overhead.

## 2. High-Level System Diagram

The diagram below illustrates the main components of the PULSAR SoC and their interactions.

```
+--------------------------------------------------------------------------+
| PULSAR SoC (FPGA)                                                        |
|                                                                          |
|  +----------------+   (Custom Instructions)   +-----------------------+  |
|  |                |-------------------------->|                       |  |
|  |   LX32K CPU    |<--------------------------|   Sensor Controller   |  |
|  |     Core       |   (Data via LX.MATRIX)    | (64-channel, parallel)|  |
|  +----------------+                           +-----------------------+  |
|      |       ^                                       |         ^         |
|      |       | (Load/Store)                          |         | (SPI)   |
| (MMIO Access) |       |                               |         |         |
|      v       |       v                               v         |         |
|  +----------------+  +----------------------+  +----------------+         |
|  | DMA Controller |  |   Data BRAM (64KB)   |  | Sensor Buffer  |         |
|  +----------------+  | (Stack, Globals)     |  | (128B x 2)     |         |
|      |       ^       +----------------------+  +----------------+         |
|      |       |                                                            |
| (DMA Transfer) |                                                            |
|      v       |                                                            |
|  +----------------+                                                        |
|  | USB HS Phy/MAC |                                                        |
|  | (LUNA Core)    |------------------------------------------------------> To Host
|  +----------------+                                                        |
|                                                                          |
+--------------------------------------------------------------------------+
     ^
     | (Analog Signals)
     |
+-----------------------+
|  Hall Sensors (x64)   |
|  + ADCs (x8)          |
+-----------------------+
```

## 3. The Journey of a Keypress (Data Flow)

Understanding the data flow is key to understanding the architecture.

1.  **Analog Sensing:** A physical keypress moves a magnet, changing the voltage output of an SS49E Hall effect sensor.
2.  **Parallel Digitization:** Eight ADS8688 ADCs, running in parallel, simultaneously sample all 64 analog sensor signals. This process is orchestrated by the `Sensor Controller`.
3.  **Snapshot Buffering:** The `Sensor Controller` collects the 64 digital values (16 bits each) and writes them into one of two buffers in the dedicated **Sensor Data Buffer** RAM. This entire process takes < 2μs. Once a buffer is full, the controller atomically swaps to the other buffer, preventing data tearing.
4.  **Firmware Processing:** The firmware, running on the LX32K CPU, begins its main loop.
    - It calls `__builtin_lx_matrix()` (`LX.MATRIX`), which instantly returns a pointer to the latest stable sensor snapshot.
    - It iterates through the keys, using `__builtin_lx_delta()` (`LX.DELTA`) to get the velocity of each key with a single instruction.
    - Based on the position and velocity, it updates the keyboard's state (e.g., applying rapid trigger logic).
5.  **HID Report Generation:** The firmware constructs the 8-byte USB HID report in **Data BRAM**.
6.  **DMA Offload:** The firmware calls `__builtin_lx_report()` (`LX.REPORT`), passing it a pointer to the HID report. This instruction tells the `DMA Controller` to start sending the data.
7.  **USB Transmission:** The `DMA Controller` reads the 8-byte report from Data BRAM and writes it directly to the `USB HS Controller`'s endpoint buffer, which then transmits it to the host. The CPU is free to start processing the next frame while this happens.

## 4. The Hardware/Firmware Contract

To enable parallel development, we rely on two critical documents that form the contract between the hardware (RTL) team and the firmware team. **These documents are the single source of truth.**

1.  **`docs/lx32k/custom_isa.md`**:
    - **What it is:** The definitive specification for every custom instruction.
    - **Who uses it:**
        - **Axel (RTL):** Implements the logic for these instructions in the CPU and peripherals.
        - **Agustín (Firmware):** Uses the C built-ins defined here to write the keyboard firmware.
        - **Axel (LLVM):** Implements the compiler backend to turn the C built-ins into the correct machine code.

2.  **`docs/lx32k/memory_map.md`**:
    - **What it is:** The layout of the entire 32-bit address space.
    - **Who uses it:**
        - **Axel (RTL):** Implements the address decoder that routes memory accesses to the correct BRAM or peripheral.
        - **Agustín (Firmware):** Uses the MMIO addresses defined here to interact with peripherals like the OLED display or timers.
        - **Emiliano (Hardware):** Ensures the physical connections on the PCB match the peripherals defined in the memory map.

Any change to the system's memory layout or instruction set **must** be reflected in these documents before implementation begins.

