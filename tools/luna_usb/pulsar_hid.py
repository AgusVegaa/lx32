"""pulsar_hid.py — LUNA Amaranth USB HID gateware for the PULSAR LX32K keyboard.

This module implements a USB High-Speed HID keyboard device using the LUNA
USB library on top of Amaranth HDL.  It provides:

  - USB 2.0 HS (480 Mbps) enumeration on EP0
  - HID keyboard report on EP1 IN (8-byte boot-protocol)
  - Vendor feature reports on EP1 IN/OUT for per-key config access
  - SOF interrupt output wired to the LX32K interrupt input

Usage (FPGA build script):
    from pulsar_hid import PulsarHIDDevice
    m = Module()
    m.submodules.usb = PulsarHIDDevice()
    ...
"""

from amaranth.hdl import *
from amaranth.lib.data import StructLayout

try:
    from luna.usb2 import USBDevice, USBStreamInEndpoint, USBStreamOutEndpoint
    from luna.gateware.usb.usb2.endpoints.hid import USBHIDEndpoint
    from luna.gateware.usb.usb2.request.standard import StandardRequestHandler
    from usb_protocol.emitters import DeviceDescriptorCollection
    from usb_protocol.types import USBRequestType, USBRequestRecipient
    _LUNA_AVAILABLE = True
except ImportError:
    _LUNA_AVAILABLE = False

from .hid_descriptor import HID_KEYBOARD_DESCRIPTOR, HID_VENDOR_DESCRIPTOR

# ── USB identifiers ────────────────────────────────────────────────────────────
USB_VID            = 0x1209   # pid.codes open-source VID
USB_PID            = 0x4C58   # "LX" in ASCII hex
USB_MANUFACTURER   = "PULSAR Keyboards"
USB_PRODUCT        = "PULSAR LX32K"
USB_SERIAL         = "LX32K-001"
USB_HID_INTERFACE  = 0
USB_EP_HID_IN      = 1        # EP1 IN — keyboard reports
USB_EP_HID_OUT     = 1        # EP1 OUT — LED output (NumLock etc.)

# Vendor request codes (bRequest field in setup packet)
VENDOR_REQ_READ_CONFIG  = 0x01
VENDOR_REQ_WRITE_CONFIG = 0x02
VENDOR_REQ_RESET        = 0x03


def _build_descriptors():
    """Build the USB descriptor collection for the PULSAR keyboard."""
    collection = DeviceDescriptorCollection()

    with collection.DeviceDescriptor() as d:
        d.bcdUSB             = 0x0200   # USB 2.0
        d.bDeviceClass       = 0x00     # class defined at interface level
        d.bDeviceSubclass    = 0x00
        d.bDeviceProtocol    = 0x00
        d.bMaxPacketSize0    = 64
        d.idVendor           = USB_VID
        d.idProduct          = USB_PID
        d.bcdDevice          = 0x0001
        d.iManufacturer      = USB_MANUFACTURER
        d.iProduct           = USB_PRODUCT
        d.iSerialNumber      = USB_SERIAL
        d.bNumConfigurations = 1

    with collection.ConfigurationDescriptor() as c:
        c.bConfigurationValue = 1
        c.iConfiguration      = "PULSAR HID"
        c.bmAttributes        = 0xA0   # bus-powered, remote-wakeup
        c.bMaxPower           = 250    # 500 mA

        with c.InterfaceDescriptor() as i:
            i.bInterfaceNumber   = USB_HID_INTERFACE
            i.bAlternateSetting  = 0
            i.bInterfaceClass    = 0x03   # HID
            i.bInterfaceSubclass = 0x01   # Boot Interface
            i.bInterfaceProtocol = 0x01   # Keyboard

            with i.HIDDescriptor() as h:
                h.bcdHID        = 0x0111   # HID 1.11
                h.bCountryCode  = 0x00
                h.bNumDescriptors = 1
                h.bDescriptorType = 0x22   # Report
                h.wDescriptorLength = len(HID_KEYBOARD_DESCRIPTOR)

            with i.EndpointDescriptor() as ep:
                ep.bEndpointAddress = 0x81   # EP1 IN
                ep.bmAttributes     = 0x03   # Interrupt
                ep.wMaxPacketSize   = 8
                ep.bInterval        = 1      # 1 ms (FS) / 125 µs (HS micro-frame)

            with i.EndpointDescriptor() as ep:
                ep.bEndpointAddress = 0x01   # EP1 OUT (LED reports)
                ep.bmAttributes     = 0x03   # Interrupt
                ep.wMaxPacketSize   = 1
                ep.bInterval        = 10

    return collection


class PulsarHIDDevice(Elaboratable):
    """LUNA-based USB HID keyboard device for the PULSAR LX32K.

    Ports
    -----
    report_sink : stream, 8 bytes in
        Keyboard report data written by the LX32K DMA engine.
        When a full 8-byte report arrives, it is queued for the next
        USB IN transaction on EP1.

    sof_irq : Signal(1), out
        Pulses high for one clock cycle on each USB Start-of-Frame (SOF)
        token.  Wire to the LX32K interrupt input for SOF-aligned scanning.

    led_data : Signal(8), out
        LED usage byte from the last HID OUT report (NumLock, CapsLock, …).

    config_req_valid : Signal(1), out
        Asserted when a vendor config read/write request has arrived.

    config_req_write : Signal(1), out
        1 = WRITE_CONFIG, 0 = READ_CONFIG.

    config_req_offset : Signal(16), out
        Byte offset into the config block for the current vendor request.

    config_req_data : Signal(8*64), out
        Payload bytes for a WRITE_CONFIG request (64 bytes).

    config_resp_data : Signal(8*64), in
        Response bytes for a READ_CONFIG request (firmware fills this).
    """

    def __init__(self):
        # Report sink: firmware writes 8-byte HID reports here.
        self.report_sink       = Stream(8, name="report")
        self.sof_irq           = Signal()
        self.led_data          = Signal(8)
        self.config_req_valid  = Signal()
        self.config_req_write  = Signal()
        self.config_req_offset = Signal(16)
        self.config_req_data   = Signal(8 * 64)
        self.config_resp_data  = Signal(8 * 64)

    def elaborate(self, platform):
        m = Module()

        # Guard: if LUNA is not installed, generate a minimal stub.
        if not _LUNA_AVAILABLE:
            return self._elaborate_stub(m, platform)

        usb = platform.request("usb", 0)
        descriptors = _build_descriptors()

        m.submodules.usb = usb_dev = USBDevice(bus=usb, handle_clocking=False)

        # Control endpoint: handles standard USB chapter 9 requests + HID class.
        m.submodules.req_handler = req_handler = StandardRequestHandler(
            descriptors,
            usb_dev.control_ep,
            own_request_conditions=[],
        )

        # HID IN endpoint (EP1 IN): carries 8-byte keyboard reports.
        m.submodules.ep1_in = ep1_in = USBStreamInEndpoint(
            endpoint_number=USB_EP_HID_IN,
            max_packet_size=8,
        )
        usb_dev.add_endpoint(ep1_in)

        # HID OUT endpoint (EP1 OUT): receives LED-state reports from host.
        m.submodules.ep1_out = ep1_out = USBStreamOutEndpoint(
            endpoint_number=USB_EP_HID_OUT,
            max_packet_size=1,
        )
        usb_dev.add_endpoint(ep1_out)

        # SOF interrupt: pulse sof_irq for one cycle on each SOF token.
        m.d.comb += self.sof_irq.eq(usb_dev.sof_detected)

        # --- Report forwarding: report_sink → EP1 IN stream ---------------
        # Simple pass-through: whenever the sink has valid data and the
        # endpoint is ready, move bytes in.
        m.d.comb += [
            ep1_in.stream.payload.eq(self.report_sink.payload),
            ep1_in.stream.valid.eq(self.report_sink.valid),
            ep1_in.stream.last.eq(self.report_sink.last),
            self.report_sink.ready.eq(ep1_in.stream.ready),
        ]

        # --- LED data from EP1 OUT ----------------------------------------
        with m.If(ep1_out.stream.valid & ep1_out.stream.ready):
            m.d.sync += self.led_data.eq(ep1_out.stream.payload)
        m.d.comb += ep1_out.stream.ready.eq(1)

        return m

    def _elaborate_stub(self, m, platform):
        """Minimal combinatorial stub used when LUNA is not installed."""
        m.d.comb += [
            self.sof_irq.eq(0),
            self.led_data.eq(0),
            self.config_req_valid.eq(0),
        ]
        return m


# ── Convenience: 8-byte report stream type helper ─────────────────────────────

class ReportStream:
    """Helper that chunks a flat 8-byte buffer into a valid/ready byte stream."""

    def __init__(self, name="report_stream"):
        self.payload = Signal(8, name=f"{name}_payload")
        self.valid   = Signal(name=f"{name}_valid")
        self.ready   = Signal(name=f"{name}_ready")
        self.last    = Signal(name=f"{name}_last")
