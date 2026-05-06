"""config.py — Serialisation of the PULSAR per-key config block.

Mirrors the Config struct in tools/pulsar_pac/src/config.rs:

  +0x000  magic      u32  = 0x504C_5358 ("PLSX")
  +0x004  version    u32  = 1
  +0x008  actuation  64 × u16  (default 120)
  +0x088  reset      64 × u16  (default 80)
  +0x108  noise      64 × u16  (default 20)
  +0x188  layer      256 × u8
  +0x288  (end)
"""

import json
import struct
from dataclasses import dataclass, field
from typing import List

CONFIG_MAGIC   = 0x504C_5358   # "PLSX"
CONFIG_VERSION = 1
CONFIG_SIZE    = 0x288

_STRUCT_FMT = (
    "<"       # little-endian
    "II"      # magic, version
    "64H"     # actuation[64]
    "64H"     # reset[64]
    "64H"     # noise[64]
    "256B"    # layer[256]
)
assert struct.calcsize(_STRUCT_FMT) == CONFIG_SIZE, \
    f"struct size mismatch: {struct.calcsize(_STRUCT_FMT)} != {CONFIG_SIZE}"


@dataclass
class Config:
    """Per-key configuration block."""

    magic:      int           = CONFIG_MAGIC
    version:    int           = CONFIG_VERSION
    actuation:  List[int]     = field(default_factory=lambda: [120] * 64)
    reset:      List[int]     = field(default_factory=lambda: [80]  * 64)
    noise:      List[int]     = field(default_factory=lambda: [20]  * 64)
    layer:      List[int]     = field(default_factory=lambda: list(_default_layer()))

    # ── Serialisation ──────────────────────────────────────────────────────

    def to_bytes(self) -> bytes:
        return struct.pack(
            _STRUCT_FMT,
            self.magic,
            self.version,
            *self.actuation,
            *self.reset,
            *self.noise,
            *self.layer,
        )

    @classmethod
    def from_bytes(cls, data: bytes) -> "Config":
        if len(data) != CONFIG_SIZE:
            raise ValueError(f"Expected {CONFIG_SIZE} bytes, got {len(data)}")
        vals = struct.unpack(_STRUCT_FMT, data)
        idx = 0
        magic, version = vals[idx], vals[idx + 1]; idx += 2
        actuation = list(vals[idx:idx + 64]); idx += 64
        reset     = list(vals[idx:idx + 64]); idx += 64
        noise     = list(vals[idx:idx + 64]); idx += 64
        layer     = list(vals[idx:idx + 256])
        return cls(
            magic=magic,
            version=version,
            actuation=actuation,
            reset=reset,
            noise=noise,
            layer=layer,
        )

    # ── Validation ─────────────────────────────────────────────────────────

    def is_valid(self) -> bool:
        return self.magic == CONFIG_MAGIC

    # ── JSON I/O ───────────────────────────────────────────────────────────

    def to_json(self) -> str:
        return json.dumps({
            "magic":     hex(self.magic),
            "version":   self.version,
            "actuation": self.actuation,
            "reset":     self.reset,
            "noise":     self.noise,
            "layer":     self.layer,
        }, indent=2)

    @classmethod
    def from_json(cls, text: str) -> "Config":
        d = json.loads(text)
        magic = int(d.get("magic", hex(CONFIG_MAGIC)), 16) \
                if isinstance(d.get("magic"), str) else d.get("magic", CONFIG_MAGIC)
        return cls(
            magic=magic,
            version=d.get("version", CONFIG_VERSION),
            actuation=d.get("actuation", [120] * 64),
            reset=d.get("reset", [80] * 64),
            noise=d.get("noise", [20] * 64),
            layer=d.get("layer", list(_default_layer())),
        )


def default_config() -> Config:
    """Return a Config with factory defaults."""
    return Config()


def _default_layer():
    """Layer 0: keys 0-55 → HID usage (key_idx % 58 + 4); keys 56-63 → 0."""
    layer = [0] * 256
    for i in range(56):
        layer[i] = (i % 58) + 4
    return layer
