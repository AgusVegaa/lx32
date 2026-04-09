# LX32K Custom ISA Specification

This document defines the contract for the custom instructions of the LX32K processor, the core of the PULSAR keyboard. These instructions provide low-level, high-performance access to the keyboard's specialized hardware, enabling ultra-low-latency input processing.

## Summary

| Instruction | Opcode   | Funct3 | Format | Latency | Description                                       |
|-------------|----------|--------|--------|---------|---------------------------------------------------|
| `LX.SENSOR` | CUSTOM-0 | `000`  | I-Type | 1 cycle | Reads a single 16-bit sensor value.               |
| `LX.MATRIX` | CUSTOM-0 | `001`  | I-Type | 1 cycle | Gets a pointer to the 64-key sensor snapshot.     |
| `LX.DELTA`  | CUSTOM-0 | `010`  | I-Type | 1 cycle | Calculates the delta between current/previous frame. |
| `LX.CHORD`  | CUSTOM-0 | `011`  | R-Type | 1 cycle | Checks if a key combination (bitmask) is active.  |
| `LX.WAIT`   | CUSTOM-1 | `000`  | I-Type | N cycles| Stalls the pipeline for an exact number of cycles.  |
| `LX.REPORT` | CUSTOM-1 | `001`  | I-Type | 1 cycle | Initiates a DMA transfer of the HID report.       |

## Opcode Space

The custom instructions occupy the `CUSTOM-0` and `CUSTOM-1` opcode spaces reserved by the RISC-V ISA.

- **`CUSTOM-0` (`0001011`):** R-Type and I-Type instructions that interface with the sensor subsystem.
- **`CUSTOM-1` (`0101011`):** Instructions for pipeline control and DMA operations.

---

## 1. `LX.SENSOR` — Read Individual Sensor

- **Syntax:** `LX.SENSOR rd, rs1`
- **Description:** Reads the 16-bit value of a single Hall effect sensor and sign-extends it into the destination register `rd`. The sensor index is specified in `rs1`. This provides fine-grained access to a specific key's position.

### Specification

- **Encoding:**
  - **Opcode:** `CUSTOM-0` (`0001011`)
  - **funct3:** `000`
  - **Format:** I-Type
- **Latency:** **1 cycle** (fetch → decode → execute → write-back).
- **Registers:**
  - `rs1` (source): The index of the sensor to be read (0-63).
  - `rd` (destination): The 16-bit sensor value, sign-extended to 32 bits.
- **Behavior under contention:**
  - The `sensor_controller` hardware guarantees that a valid sensor value is always available. It continuously scans and buffers all 64 sensors in the background. This instruction reads from that internal buffer, so it **never stalls**.
- **Behavior (Simulation vs. Hardware):**
  - **Simulation:** The value is provided by a SystemVerilog testbench model that can simulate various conditions like noise, different keypress profiles, and variance.
  - **Hardware:** The value is the real-time digital reading from the dedicated ADC channel (ADS8688) corresponding to the addressed sensor.
- **C-language Built-in:**
  ```c
  #include <stdint.h>
  /**
   * @brief Reads the 16-bit value of the Hall effect sensor at the given index.
   * @param idx The sensor index (0-63).
   * @return The sensor's current value, sign-extended to 32 bits.
   */
  static inline int32_t __builtin_lx_sensor(uint32_t idx);
  ```

---

## 2. `LX.MATRIX` — Get Sensor Snapshot Pointer

- **Syntax:** `LX.MATRIX rd, rs1`
- **Description:** Returns a pointer to the base address of a 128-byte memory block containing the most recent snapshot of all 64 sensor values. This is the most efficient way to process the entire keyboard state at once. The `rs1` register is ignored but is part of the instruction format for consistency.

### Specification

- **Encoding:**
  - **Opcode:** `CUSTOM-0` (`0001011`)
  - **funct3:** `001`
  - **Format:** I-Type.
- **Latency:** **1 cycle**.
- **Registers:**
  - `rs1` (source): Unused.
  - `rd` (destination): The 32-bit memory address of the first element (`sensor[0]`) in the snapshot array.
- **Behavior under contention:**
  - The `sensor_controller` uses a double-buffering mechanism. While one buffer is being filled with new sensor data, the other holds the last stable snapshot. This instruction always points to the stable, complete buffer. It **never stalls**.
- **Behavior (Simulation vs. Hardware):**
  - **Simulation:** Returns a pointer to a memory region within the simulation environment, which is pre-filled by the testbench's sensor model.
  - **Hardware:** Returns the physical BRAM address where the `sensor_controller` has placed the latest complete snapshot of all 64 sensor values.
- **C-language Built-in:**
  ```c
  #include <stdint.h>
  /**
   * @brief Returns a pointer to the 64-entry array of sensor values.
   * @param col Unused. Maintained for instruction format consistency.
   * @return A pointer to the start of the uint16_t sensor_snapshot[64] array.
   */
  static inline uint16_t* __builtin_lx_matrix(uint32_t col);
  ```

---

## 3. `LX.DELTA` — Calculate Frame-to-Frame Delta

- **Syntax:** `LX.DELTA rd, rs1`
- **Description:** Calculates the difference between the current value of the sensor at index `rs1` and its value from the previous frame. The result is a signed 16-bit integer, which represents the key's velocity.

### Specification

- **Encoding:**
  - **Opcode:** `CUSTOM-0` (`0001011`)
  - **funct3:** `010`
  - **Format:** I-Type.
- **Latency:** **1 cycle**.
- **Registers:**
  - `rs1` (source): The index of the sensor (0-63).
  - `rd` (destination): The signed 16-bit delta, sign-extended to 32 bits. A positive value means the key is being pressed down; a negative value means it is being released.
- **Behavior under contention:**
  - The `sensor_controller` internally maintains two full snapshots: `current_frame` and `previous_frame`. This instruction reads from these dedicated hardware registers. It **never stalls**.
- **Behavior (Simulation vs. Hardware):**
  - Identical. The logic (`current[rs1] - previous[rs1]`) is self-contained within the `sensor_controller` in both simulation and hardware.
- **C-language Built-in:**
  ```c
  #include <stdint.h>
  /**
   * @brief Calculates the velocity of a key by subtracting its previous value from its current one.
   * @param key_idx The sensor index (0-63).
   * @return The signed 16-bit delta, representing velocity.
   */
  static inline int32_t __builtin_lx_delta(uint32_t key_idx);
  ```

---

## 4. `LX.CHORD` — Match Key State Bitmask

- **Syntax:** `LX.CHORD rd, rs1`
- **Description:** Compares a 32-bit mask in `rs1` against the current state of the first 32 keys. If every key corresponding to a `1` in the bitmask is currently active (i.e., pressed), `rd` is set to 1. Otherwise, `rd` is 0. This is used for implementing complex shortcuts and layers.

### Specification

- **Encoding:**
  - **Opcode:** `CUSTOM-0` (`0001011`)
  - **funct3:** `011`
  - **Format:** R-Type.
- **Latency:** **1 cycle**.
- **Registers:**
  - `rs1` (source): A 32-bit bitmask where each bit represents a key.
  - `rd` (destination): `1` if the chord matches, `0` otherwise.
- **Behavior under contention:**
  - The active/inactive state of all keys is maintained in a dedicated hardware register that is updated every frame. This instruction reads from that register. It **never stalls**.
- **Behavior (Simulation vs. Hardware):**
  - Identical. The comparison logic is implemented in hardware and behaves the same in simulation.
- **C-language Built-in:**
  ```c
  #include <stdint.h>
  /**
   * @brief Checks if a combination of keys is currently pressed.
   * @param bitmask A 32-bit mask representing the key chord.
   * @return 1 if all keys in the mask are active, 0 otherwise.
   */
  static inline uint32_t __builtin_lx_chord(uint32_t bitmask);
  ```

---

## 5. `LX.WAIT` — Pipeline Suspension

- **Syntax:** `LX.WAIT rd`
- **Description:** Stalls the processor pipeline by preventing the fetch of new instructions for a precise number of clock cycles, specified by the value in `rd`. This is useful for fine-grained timing control, such as debouncing or synchronizing with external hardware.

### Specification

- **Encoding:**
  - **Opcode:** `CUSTOM-1` (`0101011`)
  - **funct3:** `000`
  - **Format:** I-Type (uses `rd` as the source operand).
- **Latency:** **N cycles**, where N is the value in `rd`.
- **Registers:**
  - `rd` (source): The number of clock cycles to wait.
- **Behavior under contention:**
  - Not applicable. This instruction directly controls the pipeline.
- **Behavior (Simulación vs. Hardware):**
  - Identical. In both scenarios, the `control_unit` gates the program counter for exactly N cycles.
- **C-language Built-in:**
  ```c
  #include <stdint.h>
  /**
   * @brief Stalls the pipeline for a precise number of cycles.
   * @param cycles The number of clock cycles to wait.
   */
  static inline void __builtin_lx_wait(uint32_t cycles);
  ```

---

## 6. `LX.REPORT` — Initiate HID Report DMA

- **Syntax:** `LX.REPORT rs1`
- **Description:** Initiates a DMA transfer to send an 8-byte HID report to the USB controller. The memory address of the report data is specified in `rs1`. This is a non-blocking instruction from the CPU's perspective.

### Specification

- **Encoding:**
  - **Opcode:** `CUSTOM-1` (`0101011`)
  - **funct3:** `001`
  - **Format:** I-Type.
- **Latency:** **1 cycle** for the CPU. The DMA transfer proceeds in the background.
- **Registers:**
  - `rs1` (source): A pointer to the 8-byte HID report buffer in memory.
- **Behavior under contention:**
  - If the DMA engine is already busy with a previous transfer, this instruction **will stall** the pipeline until the DMA is ready to accept a new command. This is a critical feature to prevent report corruption and ensure data integrity.
- **Behavior (Simulation vs. Hardware):**
  - **Simulation:** A model of the `dma_controller` accepts the command, and a testbench task simulates the transfer delay and completion signal.
  - **Hardware:** The physical `dma_controller` initiates a bus transaction to move the 8-byte report from BRAM to the USB endpoint's dedicated buffer.
- **C-language Built-in:**
  ```c
  #include <stdint.h>
  /**
   * @brief Sends an 8-byte HID report via DMA to the USB controller.
   * @param report_ptr Pointer to the HID report data structure.
   * @note This function is non-blocking unless the DMA is already busy.
   */
  static inline void __builtin_lx_report(void* report_ptr);
  ```


