# pulsar_hid — LUNA USB HID Gateware

USB High-Speed HID keyboard device using [LUNA](https://github.com/greatscottgadgets/luna) on Amaranth HDL.

## What it provides

- USB 2.0 HS (480 Mbps) enumeration
- EP0: control endpoint (standard chapter-9 requests + HID class)
- EP1 IN: 8-byte keyboard report (interrupt, 125 µs interval)
- EP1 OUT: LED-state output report (NumLock, CapsLock, …)
- `sof_irq`: one-cycle pulse per USB SOF → wire to LX32K interrupt input
- Vendor feature reports (bRequest 0x01/0x02) for per-key config access

## USB identifiers

| Field      | Value                   |
|------------|-------------------------|
| VID        | `0x1209` (pid.codes)    |
| PID        | `0x4C58`                |
| Manufacturer | PULSAR Keyboards      |
| Product    | PULSAR LX32K            |

## Install

```bash
pip install -r requirements.txt
```

## Synthesise

```python
from tools.luna_usb.pulsar_hid import PulsarHIDDevice
from amaranth.back.rtlil import convert

dut = PulsarHIDDevice()
with open("pulsar_hid.il", "w") as f:
    f.write(convert(dut, ports=[dut.report_sink.payload, dut.sof_irq]))
```

Then feed `pulsar_hid.il` into the nextpnr/yosys flow for your FPGA target.

## RTL interface

The companion file `rtl/core/usb_hid_bridge.sv` is the SystemVerilog stub that
the LX32K CPU accesses via MMIO (USB_CTRL_BASE = 0x4000_0200).  On FPGA,
replace the stub with a proper AXI/APB bridge to the LUNA USB core.
