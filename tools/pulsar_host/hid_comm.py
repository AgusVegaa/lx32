"""hid_comm.py — Low-level USB HID communication for the PULSAR keyboard."""

import time

# USB identifiers matching pulsar_hid.py
PULSAR_VID = 0x1209
PULSAR_PID = 0x4C58
VENDOR_REPORT_ID = 0x40
VENDOR_REPORT_SIZE = 64   # bytes (excluding report ID byte)

# Vendor request codes (bRequest)
REQ_READ_CONFIG  = 0x01
REQ_WRITE_CONFIG = 0x02
REQ_RESET        = 0x03


class PulsarDevice:
    """Context manager for raw HID communication with the PULSAR keyboard.

    Usage::

        with PulsarDevice() as dev:
            dev.write_config(cfg.to_bytes())
            data = dev.read_config()
    """

    def __init__(self):
        self._dev = None

    def __enter__(self):
        try:
            import hid
        except ImportError:
            raise RuntimeError(
                "Python 'hid' package not found.  Install with: pip install hid"
            )
        self._dev = hid.device()
        try:
            self._dev.open(PULSAR_VID, PULSAR_PID)
        except OSError as exc:
            raise RuntimeError(
                f"PULSAR keyboard not found (VID={PULSAR_VID:#06x}, "
                f"PID={PULSAR_PID:#06x}).  Is the device plugged in?"
            ) from exc
        self._dev.set_nonblocking(False)
        return self

    def __exit__(self, *_):
        if self._dev is not None:
            self._dev.close()
            self._dev = None

    # ── Feature-report helpers ─────────────────────────────────────────────

    def send_vendor_report(self, request: int, offset: int, data: bytes) -> None:
        """Send a 64-byte vendor feature report.

        Payload layout:
          [0]   request code  (REQ_READ_CONFIG / REQ_WRITE_CONFIG / …)
          [1:3] offset        (little-endian u16)
          [3]   data length
          [4:]  data bytes (up to 60)
        """
        payload = bytearray(VENDOR_REPORT_SIZE)
        payload[0] = request & 0xFF
        payload[1] = offset & 0xFF
        payload[2] = (offset >> 8) & 0xFF
        payload[3] = len(data) & 0xFF
        payload[4:4 + len(data)] = data
        # HID feature report: prepend report ID
        self._dev.send_feature_report(bytes([VENDOR_REPORT_ID]) + bytes(payload))

    def recv_vendor_report(self, timeout_ms: int = 1000) -> bytes:
        """Read a 64-byte vendor feature report.  Returns payload bytes."""
        buf = self._dev.get_feature_report(VENDOR_REPORT_ID, VENDOR_REPORT_SIZE + 1)
        if not buf or buf[0] != VENDOR_REPORT_ID:
            raise RuntimeError(f"Unexpected report ID: {buf[0] if buf else 'none'}")
        return bytes(buf[1:])

    # ── High-level config access ───────────────────────────────────────────

    def read_config(self) -> bytes:
        """Read the full config block (0x288 bytes) from the device.

        Transfers the block in 60-byte chunks.
        """
        CONFIG_SIZE = 0x288
        result = bytearray(CONFIG_SIZE)
        offset = 0
        while offset < CONFIG_SIZE:
            chunk = min(60, CONFIG_SIZE - offset)
            self.send_vendor_report(REQ_READ_CONFIG, offset, b'')
            resp = self.recv_vendor_report()
            result[offset:offset + chunk] = resp[4:4 + chunk]
            offset += chunk
        return bytes(result)

    def write_config(self, data: bytes) -> None:
        """Write the full config block to the device.

        The config block must be exactly 0x288 bytes.
        Transfers in 60-byte chunks.
        """
        CONFIG_SIZE = 0x288
        if len(data) != CONFIG_SIZE:
            raise ValueError(
                f"Config block must be {CONFIG_SIZE} bytes, got {len(data)}"
            )
        offset = 0
        while offset < CONFIG_SIZE:
            chunk = data[offset:offset + 60]
            self.send_vendor_report(REQ_WRITE_CONFIG, offset, chunk)
            offset += len(chunk)

    def reset_device(self) -> None:
        """Send a reset request (restores factory defaults)."""
        self.send_vendor_report(REQ_RESET, 0, b'')
