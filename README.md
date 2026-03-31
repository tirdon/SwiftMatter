# SwiftMatter — Irrigation Controller

An ESP32-C3/C6 irrigation controller built entirely in **Embedded Swift**, using the [Matter](https://csa-iot.org/all-solutions/matter/) smart home protocol through the ESP-Matter SDK by Espressif. The device exposes an on/off switch (for valve/relay control), a DHT22 temperature/humidity sensor, a DS18B20 waterproof temperature sensor, and a capacitive soil moisture sensor — all as standard Matter endpoints controllable from Apple Home, Google Home, or any Matter-compatible app.

## Features

- **Matter over Wi-Fi** — commission and control the device from any Matter fabric (Apple Home, Google Home, etc.)
- **On/Off Switch Endpoint** — toggles external LED / relay on GPIO 9
- **DHT22 Endpoints** — reports temperature and relative humidity via standard Matter clusters
- **DS18B20 Endpoint** — reports water/soil temperature using the 1-Wire protocol
- **Capacitive Soil Moisture Endpoint** — reports soil moisture percentage via ADC
- **Physical Button** — GPIO 21 button toggles the switch state and reports back to the Matter fabric
- **Onboard LED** — GPIO 8 status LED indicates Wi-Fi connectivity
- **IR Receiver (NEC)** — TSOP38238 on GPIO 0, full NEC protocol decode with hold/repeat support, low-power ISR + `ulTaskNotifyTake` pattern

## Hardware

| Component | GPIO | Notes |
|-----------|------|-------|
| LED / Relay | 9 | Active high |
| Onboard Status LED | 8 | Active low (on = Wi-Fi disconnected) |
| Push Button | 21 | Active high, 10 ms debounce, 2 s long press |
| DHT22 (AM2301) | 4 | Open-drain, ambient temperature + humidity |
| DS18B20 | *Configurable* | Open-drain, waterproof temperature probe, 1-Wire |
| Capacitive Soil Moisture | *ADC Channel* | Analog (mapped from 0-4095 to 100%-0%) |
| IR Receiver (TSOP38238) | 0 | Input with pull-up, NEC protocol, ISR on falling edge |

## Project Structure

```
Irrigation/
├── CMakeLists.txt              # Top-level ESP-IDF / ESP-Matter project config
├── partitions.csv              # Custom partition table (OTA, NVS, coredump)
├── sdkconfig.defaults          # SDK configuration defaults
│
├── main/
│   ├── CMakeLists.txt          # Component build — Swift compiler flags & source list
│   ├── BridgingHeader.h        # C/C++ → Swift bridging (FreeRTOS, GPIO, Matter, DHT, RMT)
│   ├── idf_component.yml       # ESP Component Registry dependencies (dht, cmake_utilities)
│   ├── linker.lf               # Linker fragment
│   ├── Main.swift              # app_main entry point — wires up endpoints, tasks, button
│   ├── PhysicalDevices.swift   # LED, Button, DHT22, DS18B20, Soil Moisture, IR drivers
│   └── SwitchEndpoint.swift    # Matter endpoint definitions (switch, temp, humidity)
│
└── MatterInterface/
    ├── MatterInterface.h       # C++ shim declarations for esp_matter APIs
    ├── MatterInterface.cpp     # C++ shim implementations (callback, attribute, report)
    ├── Core.swift              # Protocol hierarchy (MatterNode/Endpoint/Cluster/Attribute)
    ├── Core+ID.swift           # Typed ClusterID / AttributeID wrappers, concrete clusters
    ├── Core+RootNode.swift     # Data model concrete structs (RootNode, Endpoint, etc.)
    ├── Matter.swift            # Matter.Node event routing, Matter.Endpoint attributes
    ├── Matter+Application.swift # Matter.Application — start, Wi-Fi event handling
    └── Matter+OnBoardLED.swift  # Onboard status LED (GPIO 8)
```

## Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                       Main.swift                                       │
│                                   app_main() → Never                                   │
│                                                                                        │
│  ┌─────────┐  ┌─────────┐  ┌───────────┐  ┌───────────┐  ┌────────────┐  ┌─────────┐   │
│  │   LED   │  │ Button  │  │   DHT22   │  │  DS18B20  │  │ Soil Moist │  │   IR    │   │
│  │ GPIO 9  │  │ GPIO 21 │  │  GPIO 4   │  │  1-Wire   │  │    ADC     │  │ GPIO 0  │   │
│  └────┬────┘  └────┬────┘  └─────┬─────┘  └─────┬─────┘  └──────┬─────┘  └────┬────┘   │
│       │            │             │              │               │             │        │
│       │            │        FreeRTOS task  FreeRTOS task   FreeRTOS task   GPIO ISR +  │
│       │            │        polls every    polls every     polls every    notify_take  │
│       │            │            10s            10s             10s      (blocks till)  │
│       │            │             │              │               │       (falling edge) │
│  ┌────▼────────────▼─────────────▼──────────────▼───────────────▼─────────────▼─────┐  │
│  │                                 Matter.Node                                      │  │
│  │  ┌─────────────┬───────────┬──────────────┬─────────────────┬─────────────────┐  │  │
│  │  │ SwitchEndpt │ TempEndpt │  HumidEndpt  │ DS18B20_TempEpt │ Moist_HumidEpt  │  │  │
│  │  │  (OnOff)    │  (DHT22)  │    (DHT22)   │    (DS18B20)    │       (ADC)     │  │  │
│  │  └─────────────┴───────────┴──────────────┴─────────────────┴─────────────────┘  │  │
│  └───────────────────────────────────────┬──────────────────────────────────────────┘  │
│                                          │                                             │
│  ┌───────────────────────────────────────▼──────────────────────────────────────────┐  │
│  │                              Matter.Application                                  │  │
│  │                     esp_matter.start() → Wi-Fi → Fabric                          │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **ESP-IDF** v5.3+
- **ESP-Matter** SDK (set `ESP_MATTER_PATH` environment variable)
- **Swift toolchain** with Embedded Swift support (nightly or 6.0+)
- CMake 3.29+

## Building & Flashing

```bash
# Set required environment variables
export TOOLCHAINS=org.swift.<62202602061a swift toolchain in .plist>
export IDF_PATH=<path to esp>/esp-idf
export ESP_MATTER_PATH=<path to esp>/esp-matter

# Source ESP-IDF
. $IDF_PATH/export.sh
. $ESP_MATTER_PATH/export.sh

# Set target (esp32c3 or esp32c6)
idf.py set-target esp32c3

# Build
idf.py build

# Flash & monitor
idf.py -p /dev/tty.usbserial-* flash monitor
```

## Configuration

Key settings in `sdkconfig.defaults`:

| Setting | Value | Description |
|---------|-------|-------------|
| `CONFIG_IDF_TARGET` | `esp32c3` | Target chip (override with `set-target`) |
| `CONFIG_DEFAULT_WIFI_SSID` | — | Wi-Fi network name |
| `CONFIG_DEFAULT_WIFI_PASSWORD` | — | Wi-Fi password |
| `CONFIG_ENABLE_CHIP_SHELL` | `y` | Matter CLI shell for debugging |
| `CONFIG_ENABLE_OTA_REQUESTOR` | `y` | OTA firmware updates |
| `CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING` | `y` | BLE used only during Matter commissioning |

## Matter Commissioning

After flashing, the device advertises over BLE for Matter commissioning. Use the Apple Home app, Google Home app, or `chip-tool` to commission:

```bash
# Using chip-tool
chip-tool pairing ble-wifi <node-id> <ssid> <password> <setup-pin-code> <discriminator>
```

Once commissioned, the device exposes an on/off plug-in endpoint plus any sensor endpoints you have enabled in software (DHT22 temp/humidity, DS18B20, moisture, etc.).

### Manual Interaction Examples

#### Write the Binding Entry on the Controlling Device (Switch, node 2)

Binding tells the switch which fabric, node, and endpoint it should control. Run this from the controller that owns the switch (node 2):

```bash
./chip-tool binding write binding '[{"node" : 1 , "cluster" : 6 , "endpoint" : 1}]' 2 1
```

- `node`: Node ID of the target device (e.g., 1 for the light bulb).
- `cluster`: Cluster ID to control (`6` is On/Off).
- `endpoint`: Endpoint ID on the target device (typically `1`).
- `2`: Node ID of the device writing the binding table (switch / node 2).
- `1`: Endpoint ID on the switch performing the control action.

#### Write the Access Control List on the Controlled Device (Light Bulb, node 1)

ACL entries grant permission for the switch (node 2) to send CASE-authenticated commands to the light bulb (node 1). Run from the controller that owns the bulb:

```bash
./chip-tool accesscontrol write acl '[{"privilege": 3, "authMode": 2, "subjects": [2], "targets": [{"cluster": 6, "endpoint": 1}]}]' 1 0
```

- `privilege`: `3` grants the `Operate` privilege.
- `authMode`: `2` selects CASE (certificate-authenticated session).
- `subjects`: `[2]` is the Node ID of the switch.
- `targets`: Specifies the cluster/endpoint that the switch may access (`cluster 6`, `endpoint 1`).
- `1`: Node ID where the ACL is written (light bulb).
- `0`: Endpoint ID of the Access Control cluster on the light bulb (usually endpoint 0).

## Swift ↔ ESP-Matter Bridging

The C++ ESP-Matter SDK doesn't import cleanly into Swift due to type mismatches (`uint32_t` → `UInt` vs `CUnsignedLong`). The `MatterInterface/` directory provides thin C++ shims that normalize the API:

- `set_callback_shim` — wraps the attribute callback with Swift-compatible types
- `get_shim` — cluster/attribute lookup with `unsigned int` parameters
- `update_shim` — attribute value updates
- `report_shim` — attribute reporting to the Matter fabric (for sensor value pushes)
- `get_val_shim` — attribute value retrieval by endpoint/cluster/attribute ID

### FreeRTOS Shims

FreeRTOS task notification APIs (`ulTaskNotifyTake`, `vTaskNotifyGiveFromISR`, `portYIELD_FROM_ISR`) are C macros that Swift cannot import. The following `extern "C"` wrapper functions are provided:

| Swift Function | Wraps |
|---|---|
| `ulTaskNotifyTake_shim(clearOnExit, ticks)` | `ulTaskNotifyTake` — blocks task until notified or timeout |
| `vTaskNotifyGiveFromISR_shim(handle, &woken)` | `vTaskNotifyGiveFromISR` — sends notification from ISR context |
| `portYIELD_FROM_ISR_shim(woken)` | `portYIELD_FROM_ISR` — triggers context switch if higher-priority task was woken |

## IR Receiver (NEC Protocol)

The IR subsystem uses a **TSOP38238** module on GPIO 0 to decode standard NEC infrared remote signals.

### How it works

```
Remote button press:
  TSOP38238 pulls GPIO 0 LOW → GPIO ISR fires (falling edge)
    → ISR disables interrupt, sends task notification
      → ir_rx_task wakes from ulTaskNotifyTake_shim()
        → Bit-bang NEC decode (readPulse timing)
          → handleCommand() dispatches action
            → 50ms debounce → re-enable interrupt → sleep again
```

### NEC Frame Format

| Field | Bits | Duration |
|-------|------|----------|
| AGC Leader | — | 9ms LOW + 4.5ms HIGH |
| Address | 8 | LSB first |
| Address (inverted) | 8 | Error check |
| Command | 8 | LSB first |
| Command (inverted) | 8 | Error check |
| **Repeat code** | — | 9ms LOW + 2.25ms HIGH (button held) |

### Low-Power Design

The IR task uses a **GPIO ISR + `ulTaskNotifyTake`** pattern instead of busy-polling:
- **Idle**: task is blocked (zero CPU usage), other tasks (Matter, DHT22) run normally
- **Signal**: hardware interrupt wakes the task instantly on falling edge
- **Timeout**: after 300ms of no activity, stale repeat state is cleared

## License

This project is released under the [Creative Commons Zero (CC0 1.0 Universal)](https://creativecommons.org/publicdomain/zero/1.0/) license. You can copy, modify, distribute and perform the work, even for commercial purposes, all without asking permission.
