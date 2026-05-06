"""pulsar_host — CLI for reading/writing PULSAR LX32K per-key config.

Commands
--------
  read-config               Print current device config as JSON.
  write-config FILE         Write a JSON config file to the device.
  set-key KEY ACT RST       Set actuation/reset thresholds for one key (0-63).
  set-layer LAYER KEY USAGE Set a single keymap entry (layer 0-3, key 0-63).
  reset                     Restore factory defaults on the device.

Examples
--------
  python -m pulsar_host read-config > my_config.json
  python -m pulsar_host write-config my_config.json
  python -m pulsar_host set-key 0 100 60
  python -m pulsar_host set-layer 0 0 0x04
  python -m pulsar_host reset
"""

import argparse
import sys

from .config import Config
from .hid_comm import PulsarDevice


# ── helpers ────────────────────────────────────────────────────────────────────

def _load_device_config(dev: PulsarDevice) -> Config:
    data = dev.read_config()
    cfg  = Config.from_bytes(data)
    if not cfg.is_valid():
        print("WARNING: config magic mismatch — device may be uninitialised.",
              file=sys.stderr)
    return cfg


# ── sub-commands ───────────────────────────────────────────────────────────────

def cmd_read_config(_args) -> None:
    with PulsarDevice() as dev:
        cfg = _load_device_config(dev)
    print(cfg.to_json())


def cmd_write_config(args) -> None:
    with open(args.file, "r") as fh:
        cfg = Config.from_json(fh.read())
    with PulsarDevice() as dev:
        dev.write_config(cfg.to_bytes())
    print(f"Config written ({len(cfg.to_bytes())} bytes).")


def cmd_set_key(args) -> None:
    key = args.key
    act = args.actuation
    rst = args.reset
    if not (0 <= key <= 63):
        sys.exit("KEY must be in range 0-63.")
    if not (0 <= act <= 0xFFFF):
        sys.exit("ACT must be a 16-bit unsigned value.")
    if not (0 <= rst <= 0xFFFF):
        sys.exit("RST must be a 16-bit unsigned value.")

    with PulsarDevice() as dev:
        cfg = _load_device_config(dev)
        cfg.actuation[key] = act
        cfg.reset[key]     = rst
        dev.write_config(cfg.to_bytes())
    print(f"Key {key}: actuation={act}, reset={rst}.")


def cmd_set_layer(args) -> None:
    layer = args.layer
    key   = args.key
    usage = args.usage
    if not (0 <= layer <= 3):
        sys.exit("LAYER must be in range 0-3.")
    if not (0 <= key <= 63):
        sys.exit("KEY must be in range 0-63.")
    if not (0 <= usage <= 0xFF):
        sys.exit("USAGE must be a byte value (0-255).")

    with PulsarDevice() as dev:
        cfg = _load_device_config(dev)
        cfg.layer[layer * 64 + key] = usage
        dev.write_config(cfg.to_bytes())
    print(f"Layer {layer}, key {key}: usage={usage:#04x}.")


def cmd_reset(_args) -> None:
    with PulsarDevice() as dev:
        dev.reset_device()
    print("Device reset to factory defaults.")


# ── argument parser ────────────────────────────────────────────────────────────

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python -m pulsar_host",
        description="PULSAR LX32K keyboard configurator.",
    )
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("read-config", help="Print device config as JSON.")

    p_write = sub.add_parser("write-config", help="Write JSON config to device.")
    p_write.add_argument("file", metavar="FILE", help="JSON config file path.")

    p_key = sub.add_parser("set-key", help="Set per-key thresholds.")
    p_key.add_argument("key",       metavar="KEY", type=int,
                       help="Key index (0-63).")
    p_key.add_argument("actuation", metavar="ACT", type=int,
                       help="Actuation threshold (0-65535).")
    p_key.add_argument("reset",     metavar="RST", type=int,
                       help="Reset threshold (0-65535).")

    p_layer = sub.add_parser("set-layer", help="Set a keymap entry.")
    p_layer.add_argument("layer", metavar="LAYER", type=int,
                         help="Layer index (0-3).")
    p_layer.add_argument("key",   metavar="KEY",   type=int,
                         help="Key index (0-63).")
    p_layer.add_argument("usage", metavar="USAGE", type=lambda x: int(x, 0),
                         help="HID usage code (e.g. 0x04 = 'A').")

    sub.add_parser("reset", help="Restore factory defaults.")

    return p


def main() -> None:
    parser = _build_parser()
    args   = parser.parse_args()

    dispatch = {
        "read-config":  cmd_read_config,
        "write-config": cmd_write_config,
        "set-key":      cmd_set_key,
        "set-layer":    cmd_set_layer,
        "reset":        cmd_reset,
    }
    try:
        dispatch[args.command](args)
    except RuntimeError as exc:
        sys.exit(f"Error: {exc}")


if __name__ == "__main__":
    main()
