/*
 * QEMU USB Xbox Video Chat Camera Device
 *
 * This test device exposes the original Xbox Video Chat camera VID/PID and
 * packetizes host-provided JPEG frames over an OV519-style isochronous IN
 * endpoint. The protocol coverage is intentionally conservative while the iOS
 * camera bridge is being validated.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

#include "qemu/osdep.h"
#include "qemu/error-report.h"
#include "qemu/module.h"
#include "migration/vmstate.h"
#include "hw/usb.h"
#include "hw/usb/desc.h"

#define TYPE_USB_XBOX_CAMERA "usb-xbox-camera"
#define USB_XBOX_CAMERA(obj) \
    OBJECT_CHECK(USBXboxCameraState, (obj), TYPE_USB_XBOX_CAMERA)

#define XBOX_CAMERA_VENDOR_ID 0x045e
#define XBOX_CAMERA_PRODUCT_ID 0x028c
#define XBOX_CAMERA_DEVICE_VERSION 0x0100
#define XBOX_CAMERA_EP_IN 0x01
#define XBOX_CAMERA_MAX_PACKET 896
#define XBOX_CAMERA_MAX_FRAME (512 * 1024)
#define XBOX_CAMERA_OV519_HEADER_SIZE 16

#define OV519_R25_FORMAT 0x25
#define OV519_R51_RESET1 0x51
#define OV519_R54_EN_CLK1 0x54
#define OV519_R57_SNAPSHOT 0x57
#define OV519_GPIO_DATA_OUT0 0x71
#define OV519_GPIO_IO_CTRL0 0x72
#define R51X_SYS_RESET 0x50
#define R51X_SYS_SNAP 0x52
#define R51X_SYS_INIT 0x53
#define R51X_SYS_CUST_ID 0x5f
#define R511_I2C_CTL 0x40
#define R51X_I2C_W_SID 0x41
#define R51X_I2C_SADDR_3 0x42
#define R51X_I2C_SADDR_2 0x43
#define R51X_I2C_R_SID 0x44
#define R51X_I2C_DATA 0x45
#define R518_I2C_CTL 0x47
#define R51X_I2C_STATUS_1 0x29
#define R51X_I2C_STATUS_2 0x2a

#define OV_SENSOR_PIDH 0x0a
#define OV_SENSOR_PIDL 0x0b
#define OV_SENSOR_COM7 0x12
#define OV_SENSOR_MANUFACTURER_HIGH 0x1c
#define OV_SENSOR_MANUFACTURER_LOW 0x1d
#define OV_SENSOR_COM_I 0x29
#define OV_SENSOR_BANK_SELECT 0xff

#define XBOX_CAMERA_CONTROL_LOG_LIMIT 1024
#define XBOX_CAMERA_I2C_COMPLETE 0x01

typedef size_t (*XboxCameraFrameProvider)(uint8_t *dst, size_t dst_size,
                                          uint32_t *width, uint32_t *height,
                                          uint64_t *sequence);

static XboxCameraFrameProvider camera_frame_provider;

void xemu_ios_set_xbox_camera_frame_provider(XboxCameraFrameProvider provider)
{
    camera_frame_provider = provider;
}

typedef struct USBXboxCameraState {
    USBDevice dev;
    uint8_t regs[256];
    uint8_t *frame_data;
    size_t frame_size;
    size_t frame_offset;
    uint32_t frame_width;
    uint32_t frame_height;
    uint32_t frame_counter;
    uint32_t control_log_count;
    uint32_t iso_log_count;
    uint64_t frame_sequence;
    uint8_t current_alt;
    uint8_t sensor_regs[256];
    uint8_t i2c_read_reg;
    uint8_t i2c_data_latch;
    uint8_t i2c_ctl_status;
    uint8_t sensor_bank;
    uint8_t sensor_probe_attempt;
    bool sensor_bank_identity_mode;
    bool eof_pending;
    bool streaming_requested;
} USBXboxCameraState;

typedef struct XboxCameraSensorCandidate {
    const char *name;
    uint8_t product_high;
    uint8_t product_low;
    uint8_t com_i;
} XboxCameraSensorCandidate;

static const XboxCameraSensorCandidate xbox_camera_sensor_candidates[] = {
    { "OV7648", 0x76, 0x48, 0x00 },
    { "OV7660", 0x76, 0x60, 0x00 },
    { "OV7670", 0x76, 0x73, 0x03 },
    { "OV7645", 0x76, 0x40, 0x00 },
    { "OV7620", 0x75, 0xa2, 0x02 },
    { "OV manufacturer", 0x7f, 0xa2, 0x00 },
};

enum {
    STR_MANUFACTURER = 1,
    STR_PRODUCT,
    STR_SERIALNUMBER,
    STR_INTERFACE,
};

static const USBDescStrings desc_strings = {
    [STR_MANUFACTURER] = "Microsoft",
    [STR_PRODUCT] = "Xbox Video Camera",
};

static bool xbox_camera_debug_enabled(void)
{
    static int cached = -1;

    if (cached < 0) {
        const char *value = getenv("XEMU_IOS_CAMERA_DEBUG");
        cached = value && value[0] && value[0] != '0';
    }

    return cached != 0;
}

#define CAMERA_DPRINTF(fmt, ...)                                      \
    do {                                                              \
        if (xbox_camera_debug_enabled()) {                            \
            fprintf(stderr, "[XboxCamera] " fmt "\n", ##__VA_ARGS__); \
        }                                                             \
    } while (0)

#define CAMERA_ISOC_ENDPOINT(packet_size)                                      \
    (USBDescEndpoint[])                                                        \
    {                                                                          \
        {                                                                      \
            .bEndpointAddress = USB_DIR_IN | XBOX_CAMERA_EP_IN,                \
            .bmAttributes = USB_ENDPOINT_XFER_ISOC,                            \
            .wMaxPacketSize = (packet_size),                                   \
            .bInterval = 1,                                                    \
        },                                                                     \
    }

static const USBDescIface desc_iface[] = {
    {
        .bInterfaceNumber = 0,
        .bAlternateSetting = 0,
        .bNumEndpoints = 1,
        .bInterfaceClass = USB_CLASS_VENDOR_SPEC,
        .bInterfaceSubClass = 0x00,
        .bInterfaceProtocol = 0x00,
        .eps = CAMERA_ISOC_ENDPOINT(0),
    },
    {
        .bInterfaceNumber = 0,
        .bAlternateSetting = 1,
        .bNumEndpoints = 1,
        .bInterfaceClass = USB_CLASS_VENDOR_SPEC,
        .bInterfaceSubClass = 0x00,
        .bInterfaceProtocol = 0x00,
        .eps = CAMERA_ISOC_ENDPOINT(384),
    },
    {
        .bInterfaceNumber = 0,
        .bAlternateSetting = 2,
        .bNumEndpoints = 1,
        .bInterfaceClass = USB_CLASS_VENDOR_SPEC,
        .bInterfaceSubClass = 0x00,
        .bInterfaceProtocol = 0x00,
        .eps = CAMERA_ISOC_ENDPOINT(512),
    },
    {
        .bInterfaceNumber = 0,
        .bAlternateSetting = 3,
        .bNumEndpoints = 1,
        .bInterfaceClass = USB_CLASS_VENDOR_SPEC,
        .bInterfaceSubClass = 0x00,
        .bInterfaceProtocol = 0x00,
        .eps = CAMERA_ISOC_ENDPOINT(768),
    },
    {
        .bInterfaceNumber = 0,
        .bAlternateSetting = 4,
        .bNumEndpoints = 1,
        .bInterfaceClass = USB_CLASS_VENDOR_SPEC,
        .bInterfaceSubClass = 0x00,
        .bInterfaceProtocol = 0x00,
        .eps = CAMERA_ISOC_ENDPOINT(XBOX_CAMERA_MAX_PACKET),
    },
};

static const USBDescDevice desc_device = {
    .bcdUSB = 0x0110,
    .bDeviceClass = 0x00,
    .bDeviceSubClass = 0x00,
    .bDeviceProtocol = 0x00,
    .bMaxPacketSize0 = 0x08,
    .bNumConfigurations = 1,
    .confs =
        (USBDescConfig[]){
            {
                .bNumInterfaces = 1,
                .bConfigurationValue = 1,
                .bmAttributes = USB_CFG_ATT_ONE,
                .bMaxPower = 250,
                .nif = ARRAY_SIZE(desc_iface),
                .ifs = desc_iface,
            },
        },
};

static const USBDesc desc_xbox_camera = {
    .id = {
        .idVendor = XBOX_CAMERA_VENDOR_ID,
        .idProduct = XBOX_CAMERA_PRODUCT_ID,
        .bcdDevice = XBOX_CAMERA_DEVICE_VERSION,
        .iManufacturer = STR_MANUFACTURER,
        .iProduct = STR_PRODUCT,
        .iSerialNumber = 0,
    },
    .full = &desc_device,
    .str = desc_strings,
};

static void xbox_camera_reset_stream(USBXboxCameraState *s)
{
    s->frame_size = 0;
    s->frame_offset = 0;
    s->frame_width = 0;
    s->frame_height = 0;
    s->eof_pending = false;
}

static void xbox_camera_seed_sensor(USBXboxCameraState *s)
{
    memset(s->sensor_regs, 0, sizeof(s->sensor_regs));

    /*
     * Keep the baseline as a normal OV7648-like sensor. The Xbox Video Chat
     * title loops on a page-select probe when the identity is not accepted, so
     * the read path below can cycle nearby OmniVision identities during that
     * loop without requiring one build per candidate.
     */
    s->sensor_regs[OV_SENSOR_PIDH] = 0x76;
    s->sensor_regs[OV_SENSOR_PIDL] = 0x48;
    s->sensor_regs[OV_SENSOR_COM_I] = 0x00;
    s->sensor_regs[OV_SENSOR_MANUFACTURER_HIGH] = 0x7f;
    s->sensor_regs[OV_SENSOR_MANUFACTURER_LOW] = 0xa2;
    s->sensor_regs[0x00] = 0x10;

    s->i2c_read_reg = OV_SENSOR_PIDH;
    s->i2c_data_latch = 0x00;
    s->i2c_ctl_status = XBOX_CAMERA_I2C_COMPLETE;
    s->sensor_bank = 0x00;
    s->sensor_bank_identity_mode = false;
}

static const XboxCameraSensorCandidate *
xbox_camera_current_sensor_candidate(USBXboxCameraState *s)
{
    size_t candidate = s->sensor_probe_attempt;

    if (candidate >= ARRAY_SIZE(xbox_camera_sensor_candidates)) {
        candidate = ARRAY_SIZE(xbox_camera_sensor_candidates) - 1;
    }

    return &xbox_camera_sensor_candidates[candidate];
}

static uint8_t xbox_camera_read_sensor_register(USBXboxCameraState *s,
                                                uint8_t reg)
{
    const XboxCameraSensorCandidate *candidate =
        xbox_camera_current_sensor_candidate(s);

    switch (reg) {
    case OV_SENSOR_PIDH:
        if (s->sensor_bank_identity_mode) {
            return 0x7f;
        }
        return candidate->product_high;
    case OV_SENSOR_PIDL:
        if (s->sensor_bank_identity_mode) {
            return 0xa2;
        }
        return candidate->product_low;
    case OV_SENSOR_COM_I:
        return candidate->com_i;
    case OV_SENSOR_MANUFACTURER_HIGH:
        return 0x7f;
    case OV_SENSOR_MANUFACTURER_LOW:
        return 0xa2;
    default:
        break;
    }

    return s->sensor_regs[reg];
}

static void xbox_camera_handle_i2c_ctl(USBXboxCameraState *s, uint8_t value)
{
    switch (value) {
    case 0x01: {
        uint8_t reg = s->regs[R51X_I2C_SADDR_3];
        uint8_t data = s->regs[R51X_I2C_DATA];

        if (reg == OV_SENSOR_COM7 && (data & 0x80)) {
            xbox_camera_seed_sensor(s);
        } else if (reg == OV_SENSOR_BANK_SELECT) {
            s->sensor_bank = data;
            s->sensor_regs[reg] = data;
            s->sensor_bank_identity_mode = data == 0x00;
            CAMERA_DPRINTF("sensor bank select value=0x%02x id_mode=%d probe=%u candidate=%s",
                           data, s->sensor_bank_identity_mode,
                           s->sensor_probe_attempt,
                           xbox_camera_current_sensor_candidate(s)->name);
        } else {
            s->sensor_regs[reg] = data;
        }
        CAMERA_DPRINTF("sensor write sid=0x%02x reg=0x%02x value=0x%02x",
                       s->regs[R51X_I2C_W_SID], reg, data);
        break;
    }
    case 0x03:
        s->i2c_read_reg = s->regs[R51X_I2C_SADDR_2];
        CAMERA_DPRINTF("sensor read select sid=0x%02x reg=0x%02x",
                       s->regs[R51X_I2C_R_SID], s->i2c_read_reg);
        break;
    case 0x05:
        s->i2c_data_latch =
            xbox_camera_read_sensor_register(s, s->i2c_read_reg);
        if (s->i2c_read_reg == OV_SENSOR_PIDH ||
            s->i2c_read_reg == OV_SENSOR_PIDL ||
            s->i2c_read_reg == OV_SENSOR_COM_I) {
            CAMERA_DPRINTF("sensor read reg=0x%02x value=0x%02x probe=%u candidate=%s bank=0x%02x id_mode=%d",
                           s->i2c_read_reg, s->i2c_data_latch,
                           s->sensor_probe_attempt,
                           xbox_camera_current_sensor_candidate(s)->name,
                           s->sensor_bank, s->sensor_bank_identity_mode);
        } else {
            CAMERA_DPRINTF("sensor read reg=0x%02x value=0x%02x",
                           s->i2c_read_reg, s->i2c_data_latch);
        }
        break;
    default:
        break;
    }

    /*
     * The host bridge completes synchronously in this emulated device. Some
     * guests poll the OV518 I2C control register after issuing commands, so
     * expose an idle/completed status instead of echoing the last command byte.
     */
    s->i2c_ctl_status = XBOX_CAMERA_I2C_COMPLETE;
    s->regs[R511_I2C_CTL] = XBOX_CAMERA_I2C_COMPLETE;
    s->regs[R518_I2C_CTL] = XBOX_CAMERA_I2C_COMPLETE;
}

static uint8_t xbox_camera_read_register(USBXboxCameraState *s, uint8_t reg)
{
    uint8_t value = s->regs[reg];

    switch (reg) {
    case R51X_I2C_STATUS_1:
    case R51X_I2C_STATUS_2:
        return value ? value : 0x01;
    case R511_I2C_CTL:
    case R518_I2C_CTL:
        return s->i2c_ctl_status ? s->i2c_ctl_status
                                 : XBOX_CAMERA_I2C_COMPLETE;
    case R51X_SYS_RESET:
    case OV519_R51_RESET1:
        return 0x00;
    case R51X_SYS_SNAP:
    case OV519_R57_SNAPSHOT:
        return s->streaming_requested ? 0x01 : 0x00;
    case R51X_SYS_INIT:
        return value ? value : 0xe1;
    case 0x17:
        return value ? value : 0x50;
    case 0x20:
        return value ? value : 0x0c;
    case 0x21:
        return value ? value : 0x38;
    case 0x22:
        return value ? value : 0x1d;
    case OV519_R54_EN_CLK1:
        return value ? value : 0x0f;
    case 0x46:
        return 0x00;
    case 0x55:
        return value ? value : 0x02;
    case 0x59:
        return value ? value : 0x04;
    case R51X_SYS_CUST_ID:
        return value ? value : 0x10;
    case 0xa2:
        return value ? value : 0x20;
    case 0xa3:
        return value ? value : 0x18;
    case 0xa4:
        return value ? value : 0x04;
    case 0xa5:
        return value ? value : 0x28;
    case OV519_GPIO_DATA_OUT0:
        return value ? value : 0x01;
    case OV519_GPIO_IO_CTRL0:
        return value ? value : 0xee;
    case OV519_R25_FORMAT:
        return value ? value : 0x03;
    case R51X_I2C_DATA:
        return s->i2c_data_latch;
    default:
        return value;
    }
}

static void xbox_camera_note_register_write(USBXboxCameraState *s, uint8_t reg,
                                            uint8_t value)
{
    switch (reg) {
    case R51X_SYS_RESET:
    case OV519_R51_RESET1:
        if (value) {
            xbox_camera_reset_stream(s);
            xbox_camera_seed_sensor(s);
            s->regs[reg] = 0;
        }
        break;
    case R51X_SYS_SNAP:
    case OV519_R57_SNAPSHOT:
        s->streaming_requested = value != 0;
        xbox_camera_reset_stream(s);
        break;
    case R511_I2C_CTL:
        xbox_camera_handle_i2c_ctl(s, value);
        break;
    case R518_I2C_CTL:
        xbox_camera_handle_i2c_ctl(s, value);
        break;
    default:
        break;
    }
}

static void xbox_camera_handle_reset(USBDevice *dev)
{
    USBXboxCameraState *s = USB_XBOX_CAMERA(dev);

    s->frame_counter = 0;
    s->control_log_count = 0;
    s->iso_log_count = 0;
    s->current_alt = 0;
    s->streaming_requested = false;
    s->sensor_bank = 0;
    s->sensor_probe_attempt = 0;
    s->sensor_bank_identity_mode = false;
    memset(s->regs, 0, sizeof(s->regs));
    xbox_camera_seed_sensor(s);
    xbox_camera_reset_stream(s);
    CAMERA_DPRINTF("reset");
}

static bool xbox_camera_is_vendor_register_request(int request)
{
    uint8_t request_type = (request >> 8) & 0xff;

    /*
     * The Xbox Video Chat driver uses OV519 vendor register access through
     * both device-recipient and interface-recipient requests. Treat bRequest
     * 0x01 as the register access path for either recipient so the sensor init
     * sequence sees real register state instead of generic zero-filled reads.
     */
    return (request & 0xff) == 0x01 &&
           (request_type & USB_TYPE_MASK) == USB_TYPE_VENDOR;
}

static bool xbox_camera_is_vendor_in(int request)
{
    uint8_t request_type = (request >> 8) & 0xff;

    return xbox_camera_is_vendor_register_request(request) &&
           (request_type & USB_DIR_IN) != 0;
}

static bool xbox_camera_is_vendor_out(int request)
{
    uint8_t request_type = (request >> 8) & 0xff;

    return xbox_camera_is_vendor_register_request(request) &&
           (request_type & USB_DIR_IN) == 0;
}

static void xbox_camera_handle_control(USBDevice *dev, USBPacket *p,
                                       int request, int value, int index,
                                       int length, uint8_t *data)
{
    USBXboxCameraState *s = USB_XBOX_CAMERA(dev);

    if (usb_desc_handle_control(dev, p, request, value, index, length, data) >=
        0) {
        if ((request & 0xff) == USB_REQ_SET_INTERFACE) {
            s->current_alt = value & 0xff;
            xbox_camera_reset_stream(s);
            CAMERA_DPRINTF("set interface alt=%u", s->current_alt);
        }
        CAMERA_DPRINTF("descriptor control req=0x%x value=0x%x index=0x%x len=%d",
                       request, value, index, length);
        return;
    }

    if ((request & 0xff) == USB_REQ_SET_INTERFACE) {
        CAMERA_DPRINTF("reject invalid alternate setting %d", value);
        p->status = USB_RET_STALL;
        return;
    }

    CAMERA_DPRINTF("vendor control req=0x%x value=0x%x index=0x%x len=%d",
                   request, value, index, length);

    if (xbox_camera_is_vendor_out(request)) {
        if (length > 0 && data) {
            for (int i = 0; i < length; i++) {
                uint8_t reg = (index + i) & 0xff;
                s->regs[reg] = data[i];
                xbox_camera_note_register_write(s, reg, data[i]);
                if (s->control_log_count < XBOX_CAMERA_CONTROL_LOG_LIMIT) {
                    CAMERA_DPRINTF("vendor out reg=0x%02x value=0x%02x",
                                   reg, data[i]);
                    s->control_log_count++;
                }
            }
        } else {
            /*
             * OV519 register writes commonly arrive as vendor OUT requests
             * with wValue carrying the byte and wIndex carrying the register.
             */
            uint8_t reg = index & 0xff;
            uint8_t reg_value = value & 0xff;
            s->regs[reg] = reg_value;
            xbox_camera_note_register_write(s, reg, reg_value);
            if (s->control_log_count < XBOX_CAMERA_CONTROL_LOG_LIMIT) {
                CAMERA_DPRINTF("vendor out reg=0x%02x value=0x%02x",
                               reg, reg_value);
                s->control_log_count++;
            }
        }
        p->actual_length = length;
        return;
    }

    if (xbox_camera_is_vendor_in(request) && length > 0) {
        /*
         * The Xbox driver issues 8-byte control reads while probing single
         * OV519 bridge registers. Treat the request as a one-register read and
         * zero-fill the transfer tail. Returning adjacent emulated registers in
         * the extra bytes makes the sensor probe see status bytes where a real
         * single-register transaction would be quiet.
         */
        data[0] = xbox_camera_read_register(s, index & 0xff);
        if (length > 1) {
            memset(data + 1, 0, length - 1);
        }
        if (s->control_log_count < XBOX_CAMERA_CONTROL_LOG_LIMIT) {
            CAMERA_DPRINTF("vendor in reg=0x%02x value=0x%02x len=%d tail_zero=%d",
                           index & 0xff, data[0], length, length > 1);
            s->control_log_count++;
        }
        p->actual_length = length;
        return;
    }

    if ((request & (USB_DIR_IN << 8)) && length > 0) {
        memset(data, 0, length);
        p->actual_length = length;
        return;
    }

    p->actual_length = 0;
}

static bool xbox_camera_load_frame(USBXboxCameraState *s)
{
    uint64_t sequence = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    size_t frame_size;

    if (!camera_frame_provider || !s->frame_data) {
        CAMERA_DPRINTF("host frame provider unavailable");
        return false;
    }

    frame_size = camera_frame_provider(s->frame_data, XBOX_CAMERA_MAX_FRAME,
                                       &width, &height, &sequence);
    if (frame_size < 4 || frame_size > XBOX_CAMERA_MAX_FRAME) {
        CAMERA_DPRINTF("host frame unavailable size=%zu", frame_size);
        return false;
    }

    if (s->frame_data[0] != 0xff || s->frame_data[1] != 0xd8) {
        CAMERA_DPRINTF("rejecting non-jpeg host frame size=%zu", frame_size);
        return false;
    }

    s->frame_size = frame_size;
    s->frame_offset = 0;
    s->frame_width = width;
    s->frame_height = height;
    s->frame_sequence = sequence;
    s->eof_pending = false;
    return true;
}

static void xbox_camera_write_ov519_header(uint8_t *packet, uint8_t type,
                                           size_t frame_size)
{
    memset(packet, 0, XBOX_CAMERA_OV519_HEADER_SIZE);
    packet[0] = 0xff;
    packet[1] = 0xff;
    packet[2] = 0xff;
    packet[3] = type;

    if (type == 0x51) {
        uint16_t length_units = frame_size / 8;
        packet[9] = 0x00;
        packet[14] = length_units & 0xff;
        packet[15] = length_units >> 8;
    }
}

static size_t xbox_camera_packet_size_for_alt(uint8_t alt, size_t requested)
{
    static const size_t alt_sizes[] = { 0, 384, 512, 768, 896 };
    size_t max_size = alt < ARRAY_SIZE(alt_sizes) ? alt_sizes[alt] : 0;

    return MIN(requested, max_size);
}

static void xbox_camera_handle_data(USBDevice *dev, USBPacket *p)
{
    USBXboxCameraState *s = USB_XBOX_CAMERA(dev);

    if (!p->ep) {
        CAMERA_DPRINTF("stall pid=%d missing endpoint size=%zu", p->pid,
                       p->iov.size);
        p->status = USB_RET_STALL;
        return;
    }

    if (p->pid == USB_TOKEN_IN && p->ep->nr == XBOX_CAMERA_EP_IN) {
        uint8_t packet[XBOX_CAMERA_MAX_PACKET];
        size_t packet_size = xbox_camera_packet_size_for_alt(s->current_alt,
                                                             p->iov.size);
        size_t actual = 0;

        if (packet_size == 0) {
            p->status = USB_RET_NAK;
            return;
        }

        memset(packet, 0, packet_size);
        if (s->eof_pending) {
            xbox_camera_write_ov519_header(packet, 0x51, s->frame_size);
            actual = MIN(packet_size, (size_t)XBOX_CAMERA_OV519_HEADER_SIZE);
            s->eof_pending = false;
            s->frame_size = 0;
            s->frame_offset = 0;
            s->frame_counter++;
        } else {
            if (s->frame_size == 0 && !xbox_camera_load_frame(s)) {
                p->status = USB_RET_NAK;
                return;
            }

            if (s->frame_offset == 0) {
                size_t payload_capacity =
                    packet_size > XBOX_CAMERA_OV519_HEADER_SIZE
                        ? packet_size - XBOX_CAMERA_OV519_HEADER_SIZE
                        : 0;
                size_t chunk = MIN(payload_capacity, s->frame_size);

                xbox_camera_write_ov519_header(packet, 0x50, s->frame_size);
                memcpy(packet + XBOX_CAMERA_OV519_HEADER_SIZE,
                       s->frame_data, chunk);
                s->frame_offset += chunk;
                actual = XBOX_CAMERA_OV519_HEADER_SIZE + chunk;
            } else {
                size_t remaining = s->frame_size - s->frame_offset;
                size_t chunk = MIN(packet_size, remaining);

                memcpy(packet, s->frame_data + s->frame_offset, chunk);
                s->frame_offset += chunk;
                actual = chunk;
            }

            if (s->frame_offset >= s->frame_size) {
                s->eof_pending = true;
            }
        }

        usb_packet_copy(p, packet, actual);
        if (s->iso_log_count < 24 || (s->iso_log_count % 300) == 0) {
            CAMERA_DPRINTF("iso in alt=%u packet=%zu actual=%zu frame=%u jpeg=%zu seq=%llu",
                           s->current_alt, packet_size, actual,
                           s->frame_counter, s->frame_size,
                           (unsigned long long)s->frame_sequence);
        }
        s->iso_log_count++;
        return;
    }

    CAMERA_DPRINTF("stall pid=%d ep=%d size=%zu", p->pid, p->ep->nr,
                   p->iov.size);
    p->status = USB_RET_STALL;
}

static void xbox_camera_realize(USBDevice *dev, Error **errp)
{
    USBXboxCameraState *s = USB_XBOX_CAMERA(dev);

    if (desc_xbox_camera.id.iSerialNumber != 0) {
        usb_desc_create_serial(dev);
    }
    usb_desc_init(dev);

    s->frame_data = g_malloc0(XBOX_CAMERA_MAX_FRAME);
    s->frame_counter = 0;
    s->control_log_count = 0;
    s->iso_log_count = 0;
    s->current_alt = 0;
    s->streaming_requested = false;
    memset(s->regs, 0, sizeof(s->regs));
    xbox_camera_seed_sensor(s);
    xbox_camera_reset_stream(s);
    warn_report("Xbox Video Chat camera device attached; waiting for host "
                "JPEG frames");
}

static void xbox_camera_unrealize(USBDevice *dev)
{
    USBXboxCameraState *s = USB_XBOX_CAMERA(dev);

    g_clear_pointer(&s->frame_data, g_free);
}

static const VMStateDescription xbox_camera_vmstate = {
    .name = TYPE_USB_XBOX_CAMERA,
    .version_id = 1,
    .minimum_version_id = 1,
    .fields =
        (VMStateField[]){
            VMSTATE_USB_DEVICE(dev, USBXboxCameraState),
            VMSTATE_UINT32(frame_counter, USBXboxCameraState),
            VMSTATE_UINT64(frame_sequence, USBXboxCameraState),
            VMSTATE_UINT8(current_alt, USBXboxCameraState),
            VMSTATE_BOOL(streaming_requested, USBXboxCameraState),
            VMSTATE_END_OF_LIST(),
        },
};

static void xbox_camera_class_init(ObjectClass *klass, const void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    USBDeviceClass *uc = USB_DEVICE_CLASS(klass);

    uc->product_desc = "Microsoft Xbox Video Chat Camera";
    uc->usb_desc = &desc_xbox_camera;
    uc->realize = xbox_camera_realize;
    uc->unrealize = xbox_camera_unrealize;
    uc->handle_reset = xbox_camera_handle_reset;
    uc->handle_control = xbox_camera_handle_control;
    uc->handle_data = xbox_camera_handle_data;
    uc->handle_attach = usb_desc_attach;

    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
    dc->vmsd = &xbox_camera_vmstate;
    dc->desc = "Microsoft Xbox Video Chat Camera";
}

static const TypeInfo info_xbox_camera = {
    .name = TYPE_USB_XBOX_CAMERA,
    .parent = TYPE_USB_DEVICE,
    .instance_size = sizeof(USBXboxCameraState),
    .class_init = xbox_camera_class_init,
};

static void xbox_camera_register_types(void)
{
    type_register_static(&info_xbox_camera);
}

type_init(xbox_camera_register_types)
