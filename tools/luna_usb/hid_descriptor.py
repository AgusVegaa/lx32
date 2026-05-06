"""hid_descriptor.py — USB HID report descriptor for PULSAR keyboard.

Produces an 8-byte boot-protocol keyboard report:
  [0]   modifier byte  (bit-mask: LCtrl=0, LShift=1, ..., RMeta=7)
  [1]   reserved
  [2:8] up to 6 simultaneous key usage IDs
"""

# Standard USB HID keyboard descriptor (boot-protocol, 6KRO).
HID_KEYBOARD_DESCRIPTOR = bytes([
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x06,        # Usage (Keyboard)
    0xA1, 0x01,        # Collection (Application)

    # --- Modifier keys (8 × 1-bit) ---
    0x05, 0x07,        #   Usage Page (Key Codes)
    0x19, 0xE0,        #   Usage Minimum (224 = Left Control)
    0x29, 0xE7,        #   Usage Maximum (231 = Right GUI)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x01,        #   Logical Maximum (1)
    0x75, 0x01,        #   Report Size (1 bit)
    0x95, 0x08,        #   Report Count (8)
    0x81, 0x02,        #   Input (Data, Variable, Absolute)

    # --- Reserved byte ---
    0x95, 0x01,        #   Report Count (1)
    0x75, 0x08,        #   Report Size (8 bits)
    0x81, 0x01,        #   Input (Constant)

    # --- 6-key array ---
    0x95, 0x06,        #   Report Count (6)
    0x75, 0x08,        #   Report Size (8 bits)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0xFF,        #   Logical Maximum (255)
    0x05, 0x07,        #   Usage Page (Key Codes)
    0x19, 0x00,        #   Usage Minimum (0)
    0x29, 0xFF,        #   Usage Maximum (255)
    0x81, 0x00,        #   Input (Data, Array)

    0xC0,              # End Collection
])

# Vendor-defined feature report descriptor for config read/write.
# Report ID 0x40: 64-byte payload for config block access.
HID_VENDOR_DESCRIPTOR = bytes([
    0x06, 0x00, 0xFF,  # Usage Page (Vendor-defined 0xFF00)
    0x09, 0x01,        # Usage (Vendor Usage 1)
    0xA1, 0x01,        # Collection (Application)

    0x09, 0x01,        #   Usage (Vendor Usage 1)
    0x15, 0x00,        #   Logical Minimum (0)
    0x26, 0xFF, 0x00,  #   Logical Maximum (255)
    0x75, 0x08,        #   Report Size (8 bits)
    0x95, 0x40,        #   Report Count (64 bytes)
    0x85, 0x40,        #   Report ID (0x40)
    0xB2, 0x02, 0x01,  #   Feature (Data, Variable, Absolute, Buffered Bytes)

    0xC0,              # End Collection
])
