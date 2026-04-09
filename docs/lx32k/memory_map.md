# LX32K Memory Map

This document specifies the memory map for the LX32K system-on-a-chip, the heart of the PULSAR keyboard. A clearly defined memory map is crucial for preventing conflicts between different hardware blocks and for providing a stable interface for firmware development.

## Overview

The LX32K uses a 32-bit address space. The memory is divided into several key regions:

- **Instruction BRAM:** Stores the firmware code.
- **Data BRAM:** Used for the stack, global variables, and other general-purpose data.
- **Sensor Snapshot Buffer:** A dedicated region where the `sensor_controller` stores the state of all 64 keys.
- **MMIO (Memory-Mapped I/O):** A region for controlling peripherals like the `sensor_controller`, DMA, USB, and OLED display.

## Memory Layout Diagram

```
              Address Range
            +---------------------+
0x0000_0000 | Instruction BRAM    | 32 KB
            | (Firmware Code)     |
            |                     |
0x0000_7FFF |---------------------|
0x0000_8000 |      (Unused)       |
            |                     |
0x0000_FFFF |---------------------|
0x0001_0000 | Data BRAM           | 64 KB
            | (Stack, Globals)    |
            |                     |
0x0001_FFFF |---------------------|
            |      (Unused)       |
            |       ...           |
0x3FFF_FFFF |---------------------|
0x4000_0000 | MMIO Region Start   |
            |---------------------|
0x4000_0000 | sensor_controller   | 256 B
0x4000_00FF |---------------------|
0x4000_0100 | dma_controller      | 256 B
0x4000_01FF |---------------------|
0x4000_0200 | usb_hid_controller  | 256 B
0x4000_02FF |---------------------|
0x4000_0300 | oled_spi_controller | 256 B
0x4000_03FF |---------------------|
0x4000_0400 | timer_registers     | 256 B
0x4000_04FF |---------------------|
            |      (Unused)       |
            |       ...           |
0x4FFF_FFFF |---------------------|
0x5000_0000 | Sensor Data Buffer  | 64 KB
            | (Double Buffered)   |
            |                     |
0x5000_FFFF |---------------------|
            |      (Unused)       |
            |       ...           |
0xFFFF_FFFF +---------------------+
```

## Region Details

### 1. Instruction BRAM (`0x0000_0000` - `0x0000_7FFF`)
- **Size:** 32 KB
- **Description:** A block of on-chip Block RAM dedicated to storing the executable firmware. This memory is read-only from the CPU's perspective after the initial bootload. It is connected to the instruction fetch port of the LX32K core.

### 2. Data BRAM (`0x0001_0000` - `0x0001_FFFF`)
- **Size:** 64 KB
- **Description:** A general-purpose Block RAM for all data manipulated by the firmware. This includes the call stack, global variables, and any dynamically allocated data structures. It is connected to the Load/Store Unit (LSU) of the processor.

### 3. Memory-Mapped I/O (MMIO) (`0x4000_0000` - `0x4FFF_FFFF`)
This region is used to configure and control the various hardware peripherals in the system. Each peripheral is assigned a small, dedicated block of address space.

- **`sensor_controller` (`0x4000_0000` - `0x4000_00FF`):**
  - Registers for configuring the sensor scanning rate, enabling/disabling channels, and reading status flags (e.g., `snapshot_ready`).
- **`dma_controller` (`0x4000_0100` - `0x4000_01FF`):**
  - Registers for initiating DMA transfers. This includes setting the source address (e.g., HID report buffer), destination address (USB endpoint), and transfer length.
- **`usb_hid_controller` (`0x4000_0200` - `0x4000_02FF`):**
  - Registers for managing the USB connection, reading endpoint status, and handling USB events.
- **`oled_spi_controller` (`0x4000_0300` - `0x4000_03FF`):**
  - SPI control and data registers for sending commands and pixel data to the OLED display.
- **`timer_registers` (`0x4000_0400` - `0x4000_04FF`):**
  - General-purpose timers for firmware use, capable of generating interrupts or being polled.

### 4. Sensor Data Buffer (`0x5000_0000` - `0x5000_FFFF`)
- **Size:** 64 KB
- **Description:** A large, dedicated BRAM region where the `sensor_controller` stores the complete, double-buffered snapshots of all 64 sensor values. The `LX.MATRIX` instruction returns a pointer to an address within this region.
- **Double Buffering:** The `sensor_controller` writes to one half of this buffer while the CPU can safely read from the other half, ensuring that the firmware always has access to a consistent and complete frame of data without risk of a race condition. The `sensor_controller` is responsible for swapping the buffers atomically after each full scan.

