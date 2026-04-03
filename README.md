# SwiftMatter — Irrigation Controller

An ESP32-C6 irrigation controller built in **Embedded Swift**, using the [Matter](https://csa-iot.org/all-solutions/matter/) smart home protocol through Espressif's ESP-Matter SDK. Exposes an on/off light switch endpoint for relay control, with device-to-device binding and offline SPI communication — controllable from Apple Home, Google Home, or any Matter-compatible app.

## Features

- **Matter over Wi-Fi** — commission and control the device from any Matter fabric
- **On/Off Light Switch Endpoint** — toggles bound remote devices via Matter binding
- **Physical Button** — GPIO 1 button sends Toggle command to bound devices
- **IR Receiver (NEC)** — TSOP38238 on GPIO 2, full NEC decode with repeat support, ISR + `ulTaskNotifyTake` low-power pattern
- **Bound Device State Sync** — reads back OnOff state from bound devices after each command via `OnOffReadCallback`
- **Onboard Status LED** — GPIO 15 (active-low) indicates Wi-Fi connectivity
- **SPI Master** — offline device-to-device communication via configurable SPI bus

## Hardware

| Component | GPIO | Notes |
|-----------|------|-------|
| LED | 22 | Active high, ground on GPIO 16 |
| Status LED | 15 | Active low (on = Wi-Fi disconnected) |
| Push Button | 1 | Pull-up, 30 ms debounce |
| IR Receiver (TSOP38238) | 2 | Pull-up, NEC protocol, ISR on falling edge |
| SPI (MOSI/MISO/SCLK/CS) | Configurable | Master mode, full-duplex |
| DHT22 / DS18B20 / Soil Moisture | — | Currently commented out |

## Project Structure

```
Irrigation/
├── CMakeLists.txt              # Top-level ESP-IDF / ESP-Matter project config
├── partitions.csv              # Custom partition table (OTA, NVS, coredump)
├── sdkconfig.defaults          # SDK configuration defaults
│
├── main/
│   ├── CMakeLists.txt          # Component build — Swift compiler flags & source list
│   ├── BridgingHeader.h        # C/C++ → Swift bridging (FreeRTOS, GPIO, Matter, RMT)
│   ├── idf_component.yml       # ESP Component Registry dependencies
│   ├── linker.lf               # Linker fragment
│   ├── Main.swift              # app_main entry point — wires up endpoints and tasks
│   ├── PhysicalDevices.swift   # LED, Button, IR receiver drivers
│   ├── SPI.swift               # SPI master driver (SPIDevice)
│   └── SwitchEndpoint.swift    # Matter endpoint type definitions and send_command()
│
└── MatterInterface/
    ├── MatterInterface.h       # C++ shim declarations for esp_matter APIs
    ├── MatterInterface.cpp     # C++ shim implementations + on_server_update callbacks
    ├── Core.swift              # Protocol hierarchy (MatterNode/Endpoint/Cluster/Attribute)
    ├── Core+ID.swift           # Typed ClusterID / AttributeID wrappers
    ├── Core+RootNode.swift     # Data model concrete structs (RootNode, Endpoint, etc.)
    ├── Matter.swift            # Matter.Node event routing, Matter.Endpoint attributes
    ├── Matter+Application.swift # Matter.Application — start, Wi-Fi/fabric event handling
    └── Matter+OnBoardLED.swift  # Onboard status LED (GPIO 15)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Main.swift                             │
│                      app_main() → Never                         │
│                                                                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                          │
│  │   LED   │  │ Button  │  │   IR    │                          │
│  │ GPIO 22 │  │ GPIO 1  │  │ GPIO 2  │                          │
│  └────┬────┘  └────┬────┘  └────┬────┘                          │
│       │            │            │                               │
│       │       FreeRTOS task  GPIO ISR +                         │
│       │       polls every    notify_take                        │
│       │           10ms      (blocks till                        │
│       │            │        falling edge)                       │
│  ┌────▼────────────▼────────────▼────────────────────────────┐  │
│  │                      Matter.Node                          │  │
│  │  ┌──────────────────────────────────────────────────┐     │  │
│  │  │ SwitchClientEndpoint (on_off_light_switch)       │     │  │
│  │  │ → send_command() → cluster_update_shim           │     │  │
│  │  └──────────────────────────────────────────────────┘     │  │
│  └─────────────────────────────┬─────────────────────────────┘  │
│                                │                                │
│  ┌─────────────────────────────▼─────────────────────────────┐  │
│  │                     Matter.Application                    │  │
│  │              esp_matter.start() → Wi-Fi → Fabric          │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Boot Sequence

```swift
app_main() {
    1. init_client_callbacks_shim()   // register on_server_update before Matter starts
    2. Matter.Application.start()     // start Matter stack (Wi-Fi, BLE, fabric)
    3. poll is_started()              // wait for Matter platform layer to initialize
    4. button.start()                 // launch button FreeRTOS task
    5. ir.start()                     // launch IR receiver FreeRTOS task
}
```

## Matter Binding — Command and Response Flow

This controller acts as a **light switch client** bound to one or more remote devices (e.g. a light bulb). The Matter binding mechanism handles both sending commands and reading back state.

### Data Flow

```
[This Controller]                     [Bound Device]
      |                                     |
      |--- INVOKE_CMD (Toggle) ------------>|
      |                                     | (updates its OnOff attribute)
      |<-- Command Status (OK) -------------|
      |                                     |
      |--- READ_ATTR (OnOff) -------------->|  (issued automatically after invoke)
      |                                     |
      |<-- OnAttributeData (true/false) ----|
      |                                     |
 OnOffReadCallback                          |
 -> update_local_led_shim(val)              |
 -> local LED syncs to bound device state   |
```

### `on_server_update()` Dispatch (MatterInterface.cpp)

The binding client calls `on_server_update` for each interaction with a bound device:

| Type | Trigger | Action |
|------|---------|--------|
| `INVOKE_CMD` | Button press or IR command calls `send_command()` | Forwards Toggle/On/Off to the bound device, then issues a `READ_ATTR` to read back the new OnOff state |
| `READ_ATTR` | Matter binding client (e.g. after reconnection) | Reads the remote OnOff attribute; `OnOffReadCallback::OnAttributeData()` calls `update_local_led_shim()` to sync the local LED |

### `OnOffReadCallback` — Response Handler

Inherits `chip::app::ReadClient::Callback`. This is where the bound device's state arrives:

| Method | Called When |
|--------|-------------|
| `OnAttributeData()`  | Attribute data arrives — reads the OnOff bool, syncs local LED via `update_local_led_shim()` |
| `OnError()`| Communication error with bound device |
| `OnDone()` | Read interaction completed |

The bound device does **not** need any special response code. The Matter protocol handles responses automatically — the bound device just updates its OnOff attribute, and the read request retrieves it.

## Prerequisites

- **ESP-IDF** v5.4+
- **ESP-Matter** SDK release/v1.5 (set `ESP_MATTER_PATH`)
- **Swift toolchain** with Embedded Swift support (nightly or 6.0+)
- CMake 3.29+

## Building & Flashing

```bash
# Set required environment variables
export TOOLCHAINS=org.swift.<version>
export IDF_PATH=<path>/esp-idf
export ESP_MATTER_PATH=<path>/esp-matter

# Source ESP-IDF and ESP-Matter
. $IDF_PATH/export.sh
. $ESP_MATTER_PATH/export.sh

# Set target
idf.py set-target esp32c6

# Build
idf.py build

# Flash & monitor
idf.py -p /dev/tty.usbserial-* flash monitor
```

## Configuration

Key settings in `sdkconfig.defaults`:

| Setting | Value | Description |
|---------|-------|-------------|
| `CONFIG_IDF_TARGET` | `esp32c6` | Target chip |
| `CONFIG_DEFAULT_WIFI_SSID` | — | Wi-Fi network name |
| `CONFIG_DEFAULT_WIFI_PASSWORD` | — | Wi-Fi password |
| `CONFIG_ENABLE_CHIP_SHELL` | `y` | Matter CLI shell for debugging |
| `CONFIG_ENABLE_OTA_REQUESTOR` | `y` | OTA firmware updates |
| `CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING` | `y` | BLE only during commissioning |

## Matter Commissioning

After flashing, the device starts BLE advertising for Matter commissioning. Use the Apple Home app, Google Home app, or `chip-tool`:

```bash
chip-tool pairing ble-wifi <node-id> <ssid> <password> <setup-pin-code> <discriminator>
```

## Swift / C++ Bridging

The C++ ESP-Matter SDK doesn't import cleanly into Embedded Swift due to type mismatches (`uint32_t` maps to `UInt` not `CUnsignedLong`). `MatterInterface/` provides thin C++ shims:

### Matter Attribute Shims

| Swift Function | Wraps |
|---|---|
| `set_callback_shim` | Attribute callback with Swift-compatible types |
| `get_shim` | Cluster/attribute lookup with `unsigned int` params |
| `update_shim` | Attribute value updates |
| `report_shim` | Attribute reporting to the Matter fabric |
| `get_val_shim` | Attribute value retrieval by endpoint/cluster/attribute ID |
| `cluster_update_shim` | Invoke command on a bound device (with `is_started()` guard) |
| `init_client_callbacks_shim` | Register `on_server_update` / `on_group_request` callbacks |

### FreeRTOS Shims

FreeRTOS task notification APIs are C macros invisible to Swift:

| Swift Function | Wraps |
|---|---|
| `ulTaskNotifyTake_shim(clearOnExit, ticks)` | `ulTaskNotifyTake` — blocks until notified or timeout |
| `vTaskNotifyGiveFromISR_shim(handle, &woken)` | `vTaskNotifyGiveFromISR` — sends notification from ISR |
| `portYIELD_FROM_ISR_shim(woken)` | `portYIELD_FROM_ISR` — context switch if higher-priority task woken |
| `xTaskNotifyGive_shim(handle)` | `xTaskNotifyGive` — sends notification from task context |

### SPI Master Shims

ESP-IDF SPI structs are cumbersome to initialize from Embedded Swift:

| Swift Function | Wraps |
|---|---|
| `spi_bus_init_shim(host, mosi, miso, sclk, maxSize)` | `spi_bus_initialize` with `spi_bus_config_t` |
| `spi_add_device_shim(host, cs, hz, mode, queueSz, &handle)` | `spi_bus_add_device` with `spi_device_interface_config_t` |
| `spi_transfer_shim(handle, txBuf, rxBuf, len)` | `spi_device_transmit` with `spi_transaction_t` |
| `spi_remove_device_shim(handle)` | `spi_bus_remove_device` |
| `spi_bus_free_shim(host)` | `spi_bus_free` |

## IR Receiver (NEC Protocol)

Uses a **TSOP38238** on GPIO 2 to decode NEC infrared remote signals.

```
Remote button press:
  TSOP38238 pulls GPIO 2 LOW → GPIO ISR fires (falling edge)
    → ISR disables interrupt, sends task notification
      → ir_rx_task wakes from ulTaskNotifyTake_shim()
        → Bit-bang NEC decode (readPulse timing)
          → handleCommand() → send_command() to bound device
            → 1s debounce → re-enable interrupt → sleep
```

### NEC Frame Format

| Field | Bits | Duration |
|-------|------|----------|
| AGC Leader | — | 9 ms LOW + 4.5 ms HIGH |
| Address | 8 | LSB first |
| Address (inverted) | 8 | Error check |
| Command | 8 | LSB first |
| Command (inverted) | 8 | Error check |
| Repeat code | — | 9 ms LOW + 2.25 ms HIGH (button held) |

### Low-Power Design

The IR task uses **GPIO ISR + `ulTaskNotifyTake`** instead of busy-polling:
- **Idle**: task is blocked (zero CPU), other tasks run normally
- **Signal**: hardware interrupt wakes the task instantly on falling edge
- **Timeout**: after 300 ms of no activity, stale repeat state is cleared

## SPI Master (Offline Device-to-Device)

`SPIDevice` in `main/SPI.swift` provides SPI master communication for talking to another microcontroller without WiFi/Matter.

```swift
let spi = SPIDevice(host: 1, mosi: GPIO_NUM_6, miso: GPIO_NUM_7,
                    sclk: GPIO_NUM_10, cs: GPIO_NUM_11)

spi.transfer(tx: txPtr, rx: rxPtr, length: 4)   // full-duplex
spi.send(dataPtr, length: 2)                     // send only
spi.receive(bufPtr, length: 8)                   // receive only
spi.command(0x01, response: bufPtr, responseLength: 4)  // cmd + response
```

For periodic polling, call `spi.start()` to launch a background FreeRTOS task. Use `spi.enqueue(tx:length:)` to send data and `spi.onReceive` to handle responses.

## License

This project is released under the [Creative Commons Zero (CC0 1.0 Universal)](https://creativecommons.org/publicdomain/zero/1.0/) license.
