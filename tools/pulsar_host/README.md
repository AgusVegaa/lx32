# pulsar_host — PULSAR LX32K Host Configurator

Python CLI for reading and writing the per-key config block on a connected
PULSAR LX32K keyboard over USB HID vendor feature reports.

## Install

```bash
pip install -r tools/pulsar_host/requirements.txt
```

> **macOS / Linux**: you may need `sudo` or a udev rule for raw HID access.
> **Windows**: install the [hidapi](https://github.com/libusb/hidapi) DLL.

## Usage

```
python -m pulsar_host <command> [args]
```

### Commands

| Command | Description |
|---------|-------------|
| `read-config` | Dump the device config as JSON to stdout |
| `write-config FILE` | Write a JSON config file to the device |
| `set-key KEY ACT RST` | Override actuation/reset thresholds for one key |
| `set-layer LAYER KEY USAGE` | Set a single keymap entry |
| `reset` | Restore factory defaults |

### Examples

```bash
# Dump current config
python -m pulsar_host read-config > my_config.json

# Edit and re-flash
$EDITOR my_config.json
python -m pulsar_host write-config my_config.json

# Lower actuation point on key 0 to 100, reset at 60
python -m pulsar_host set-key 0 100 60

# Map layer 1, key 5 to HID usage 0x29 (Escape)
python -m pulsar_host set-layer 1 5 0x29

# Reset to factory defaults
python -m pulsar_host reset
```

## Config JSON format

```json
{
  "magic":     "0x504c5358",
  "version":   1,
  "actuation": [120, 120, ...],   // 64 × u16
  "reset":     [80,  80,  ...],   // 64 × u16
  "noise":     [20,  20,  ...],   // 64 × u16
  "layer":     [4, 5, 6, ...]     // 256 × u8 (4 layers × 64 keys)
}
```

Default thresholds: actuation=120, reset=80, noise=20 (raw Hall ADC units).

## USB identifiers

| Field | Value |
|-------|-------|
| VID | `0x1209` (pid.codes) |
| PID | `0x4C58` |
| Vendor report ID | `0x40` |
| Report size | 64 bytes |
