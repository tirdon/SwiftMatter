# SwiftMatter — Irrigation Controller

An ESP32-C3/C6 irrigation controller built entirely in **Embedded Swift**, using the [Matter](https://csa-iot.org/all-solutions/matter/) smart home protocol. The device exposes an on/off switch (for valve/relay control), a DHT22 temperature sensor, and a DHT22 humidity sensor — all as standard Matter endpoints controllable from Apple Home, Google Home, or any Matter-compatible app.

## Features

- **Matter over Wi-Fi** — commission and control the device from any Matter fabric (Apple Home, Google Home, etc.)
- **On/Off Switch Endpoint** — toggles external LEDs / relays on GPIO 9 & 10
- **Temperature Sensor Endpoint** — reports DHT22 temperature (°C × 100) via Matter `TemperatureMeasurement` cluster
- **Humidity Sensor Endpoint** — reports DHT22 relative humidity (% × 100) via Matter `RelativeHumidityMeasurement` cluster
- **Physical Button** — GPIO 21 button toggles the switch state and reports back to the Matter fabric
- **Onboard LED** — GPIO 8 status LED indicates Wi-Fi connectivity
- **IR Receiver (NEC)** — TSOP38238 on GPIO 0, full NEC protocol decode with hold/repeat support, low-power ISR + `ulTaskNotifyTake` pattern (zero CPU usage while idle)

## Hardware

| Component | GPIO | Notes |
|-----------|------|-------|
| LED / Relay A | 10 | Active high |
| LED / Relay B | 9 | Active high (currently commented out) |
| Onboard Status LED | 8 | Active low (on = Wi-Fi disconnected) |
| Push Button | 21 | Active high, 10 ms debounce, 2 s long press |
| DHT22 (AM2301) | 4 | Open-drain, temperature + humidity |
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
│   ├── PhysicalDevices.swift   # LED, Button, DHT22Sensor, IRSensor hardware drivers
│   └── SwitchEndpoint.swift    # Matter endpoint definitions (switch, temp, humidity)
│
└── MatterInterface/
    ├── MatterInterface.h       # C++ shim declarations for esp_matter APIs
    ├── MatterInterface.cpp     # C++ shim implementations (callback, attribute, report)
    ├── Core.swift              # Protocol hierarchy (MatterNode/Endpoint/Cluster/Attribute)
    ├── Core+ID.swift           # Typed ClusterID / AttributeID wrappers, concrete clusters
    ├── Matter.swift            # Matter.Node event routing, Matter.Endpoint with Attribute enum
    ├── Matter+Application.swift # Matter.Application — start, Wi-Fi event handling, recommission
    └── Matter+OnBoardLED.swift # Onboard status LED (GPIO 8)
```

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                      Main.swift                           │
│              app_main() → Never                           │
│                                                           │
│  ┌──────────┐  ┌─────────┐  ┌────────────┐  ┌─────────┐ │
│  │   LED    │  │ Button  │  │ DHT22Sensor│  │IRSensor │ │
│  │ GPIO 10  │  │ GPIO 21 │  │   GPIO 4   │  │ GPIO 0  │ │
│  └────┬─────┘  └────┬────┘  └─────┬──────┘  └────┬────┘ │
│       │             │             │               │      │
│       │             │         FreeRTOS task    GPIO ISR + │
│       │             │        (dht_rx_task)   ulTaskNotify │
│       │             │         polls every    (ir_rx_task) │
│       │             │           ~1000s        blocks till │
│       │             │                        falling edge│
│  ┌────▼─────────────▼─────────────▼───────────────▼───┐  │
│  │                   Matter.Node                      │  │
│  │  ┌──────────────┬───────────┬───────────────┐      │  │
│  │  │ SwitchEndpt  │ TempEndpt │  HumidEndpt   │      │  │
│  │  │  (OnOff)     │ (DHT22)  │   (DHT22)     │      │  │
│  │  └──────────────┴───────────┴───────────────┘      │  │
│  └───────────────────────┬────────────────────────────┘  │
│                          │                               │
│  ┌───────────────────────▼────────────────────────────┐  │
│  │              Matter.Application                    │  │
│  │         esp_matter.start() → Wi-Fi → Fabric        │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

- **ESP-IDF** v5.3+
- **ESP-Matter** SDK (set `ESP_MATTER_PATH` environment variable)
- **Swift toolchain** with Embedded Swift support (nightly or 6.0+)
- CMake 3.29+

## Building & Flashing

```bash
# Set required environment variables
export IDF_PATH=/path/to/esp-idf
export ESP_MATTER_PATH=/path/to/esp-matter

# Source ESP-IDF
. $IDF_PATH/export.sh

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
| `CONFIG_IDF_TARGET` | `esp32c6` | Target chip (override with `set-target`) |
| `CONFIG_DEFAULT_WIFI_SSID` | — | Wi-Fi network name |
| `CONFIG_DEFAULT_WIFI_PASSWORD` | — | Wi-Fi password |
| `CONFIG_ENABLE_CHIP_SHELL` | `y` | Matter CLI shell for debugging |
| `CONFIG_ENABLE_OTA_REQUESTOR` | `y` | OTA firmware updates |
| `CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING` | `y` | BLE used only during Matter commissioning |

## Matter Commissioning

After flashing, the device will start BLE advertising for Matter commissioning. Use the Apple Home app, Google Home app, or `chip-tool` to commission:

```bash
# Using chip-tool
chip-tool pairing ble-wifi <node-id> <ssid> <password> <setup-pin-code> <discriminator>
```

Once commissioned, the device exposes three endpoints:
1. **On/Off Plug-in Unit** — toggle the irrigation relay
2. **Temperature Sensor** — DHT22 temperature readings (range: −40°C to 125°C)
3. **Humidity Sensor** — DHT22 relative humidity readings (range: 0% to 100%)

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

See individual file headers for license information. Swift bridging code follows the Apache License v2.0 with Runtime Library Exception.