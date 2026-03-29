# SwiftMatter — Thread Border Router

An ESP32-C6 **Thread Border Router** (TBR) built in **Embedded Swift**, using the [Matter](https://csa-iot.org/all-solutions/matter/) smart home protocol through the ESP-Matter SDK. The device bridges a Thread mesh network (IEEE 802.15.4) to a Wi-Fi/IP network, leveraging the ESP32-C6's dual radios. It exposes a Matter on/off switch endpoint and can auto-subscribe to bound remote Thread devices, mirroring their on/off state on a local LED.

## Features

- **Thread Border Router** — bridges Thread mesh (802.15.4) to Wi-Fi/IP using the ESP32-C6's native dual-radio hardware
- **Matter over Wi-Fi** — commission and control from any Matter fabric (Apple Home, Google Home, etc.)
- **On/Off Switch Endpoint** — toggles an external LED / relay on GPIO 16
- **Remote Device Monitoring** — auto-subscribes to bound Thread devices' OnOff cluster and mirrors state on the local LED
- **OpenThread Services** — SRP server, DNS64, NAT64, mDNS proxy, border routing agent
- **Physical Button** — GPIO 0 toggles the switch endpoint
- **Status LED** — GPIO 15 indicates Wi-Fi connectivity (active-low: lit = disconnected)
- **Binding Cluster** — controllers can bind this endpoint to remote Thread devices

## Hardware

| Component | GPIO | Notes |
|-----------|------|-------|
| LED / Relay | 16 | Active high, toggled by switch endpoint and remote mirror |
| Status LED | 15 | Active low (lit = Wi-Fi disconnected) |
| Push Button | 0 | Active low, pull-up, 50 ms debounce |

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                  Main.swift                                   │
│                              app_main() → Never                               │
│                                                                               │
│  ┌──────────┐  ┌──────────┐  ┌─────────────────────────────────────────────┐  │
│  │   LED    │  │  Button  │  │          Remote OnOff Monitor               │  │
│  │ GPIO 16  │  │  GPIO 0  │  │  Binding → CASE → Subscribe → Mirror LED    │  │
│  └────┬─────┘  └────┬─────┘  └─────────────────────┬───────────────────────┘  │
│       │             │                              │                          │
│  ┌────▼─────────────▼──────────────────────────────▼───────────────────────┐  │
│  │                            Matter.Node                                  │  │
│  │  ┌─────────────────┐  ┌──────────────┐                                  │  │
│  │  │ SwitchEndpoint  │  │   Binding    │                                  │  │
│  │  │ (OnOff Plug-in) │  │   Cluster    │                                  │  │
│  │  └─────────────────┘  └──────────────┘                                  │  │
│  └────────────────────────────────┬────────────────────────────────────────┘  │
│                                   │                                           │
│  ┌────────────────────────────────▼────────────────────────────────────────┐  │
│  │                         Matter.Application                              │  │
│  │              esp_matter.start() → Wi-Fi → Fabric → TBR init             │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────────┐ │
│  │                      OpenThread Border Router                            │ │
│  │  802.15.4 radio ←→ Thread mesh ←→ WiFi backbone ←→ IP network            │ │
│  │  SRP server · DNS64 · NAT64 · mDNS proxy · Border routing agent          │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Thread device state change
  → OpenThread mesh → 802.15.4 radio
    → Border Router forwards to IP network
      → Matter subscription delivers OnOff report
        → Swift callback mirrors state on local LED

Button press (GPIO 0)
  → FreeRTOS polling task (50 ms debounce)
    → toggleOnOff() → Matter attribute update
      → Event handler → LED toggle

Matter controller (Apple Home / Google Home)
  → Fabric command → SwitchEndpoint event
    → LED toggle
```

## Project Structure

```
Irrigation/
├── CMakeLists.txt              # Top-level ESP-IDF / ESP-Matter project config
├── partitions.csv              # Custom partition table (factory-only, no OTA)
├── sdkconfig.defaults          # SDK config: OpenThread, TBR, WiFi, Matter
│
├── main/
│   ├── CMakeLists.txt          # Component build — Swift compiler flags & source list
│   ├── BridgingHeader.h        # C/C++ → Swift bridging header
│   ├── idf_component.yml       # ESP Component Registry dependencies
│   ├── linker.lf               # Linker fragment
│   ├── Main.swift              # app_main — Matter node, switch endpoint, TBR init, button
│   └── Button.swift            # GPIO button polling task with debounce
│
└── MatterInterface/
    ├── MatterInterface.h       # C++ shim declarations (Matter, FreeRTOS, OpenThread)
    ├── MatterInterface.cpp     # C++ shim implementations + remote OnOff subscription
    ├── Core.swift              # Protocol hierarchy (MatterNode/Endpoint/Cluster/Attribute)
    ├── Core+ID.swift           # Typed ClusterID / AttributeID wrappers
    ├── Core+RootNode.swift     # Data model concrete structs
    ├── Matter.swift            # Matter.Node event routing
    ├── Matter+Application.swift # Matter.Application — start, Wi-Fi events, TBR init
    └── Matter+OnBoardLED.swift  # Status LED on GPIO 15
```

## Prerequisites

- **ESP-IDF** v5.3+
- **ESP-Matter** SDK (set `ESP_MATTER_PATH` environment variable)
- **Swift toolchain** with Embedded Swift support (nightly or 6.0+)
- **ESP32-C6** board (required for dual-radio Wi-Fi + 802.15.4)
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

# Set target (must be esp32c6 for Thread radio)
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
| `CONFIG_IDF_TARGET` | `esp32c6` | Target chip (C6 required for 802.15.4) |
| `CONFIG_OPENTHREAD_ENABLED` | `y` | Enable OpenThread stack |
| `CONFIG_OPENTHREAD_BORDER_ROUTER` | `y` | Enable border routing |
| `CONFIG_OPENTHREAD_SRP_SERVER` | `y` | SRP server for Thread service registration |
| `CONFIG_OPENTHREAD_DNS64` | `y` | DNS64 for Thread-to-IPv4 name resolution |
| `CONFIG_IEEE802154_ENABLED` | `y` | Enable 802.15.4 radio PHY |
| `CONFIG_ENABLE_CHIP_SHELL` | `y` | Matter CLI shell for debugging |
| `CONFIG_USE_BLE_ONLY_FOR_COMMISSIONING` | `y` | BLE used only during commissioning |
| `CONFIG_ESP_COEX_SW_COEXIST_ENABLE` | `y` | Wi-Fi + 802.15.4 RF coexistence |
| `CONFIG_ENABLE_OTA_REQUESTOR` | `n` | OTA disabled (binary exceeds dual-OTA capacity) |

### Stack Sizes

| Task | Size | Notes |
|------|------|-------|
| Main | 16 KB | Swift + Matter startup |
| Matter (CHIP) | 16 KB | Matter stack processing |
| BLE (NimBLE) | 8 KB | Commissioning only |
| OpenThread | 8 KB | Thread networking |
| ESP Timer | 8 KB | System timer callbacks |

## Matter Commissioning

After flashing, the device starts BLE advertising for Matter commissioning. Use the Apple Home app, Google Home app, or `chip-tool`:

```bash
# Commission via BLE-WiFi
chip-tool pairing ble-wifi <node-id> <ssid> <password> <setup-pin-code> <discriminator>
```

Once commissioned, the device exposes:
1. **On/Off Plug-in Unit** — toggle the LED/relay, with a binding cluster for remote device pairing

### Remote Device Binding

To mirror a remote Thread device's on/off state on the local LED:

1. Commission both the TBR and the remote Thread device to the same fabric
2. Create a binding from the TBR's switch endpoint to the remote device's endpoint
3. The TBR auto-subscribes to the remote device's OnOff attribute (1–30s interval)
4. State changes on the remote device are reflected on the TBR's LED

### Identifying Bound Devices

You can identify which devices are currently bound to your TBR by inspecting the Matter Binding Table. This is useful for verifying that a controller (like Apple Home) has successfully configured the device to control or monitor another.

- Use the `print_bindings_shim(endpoint_id)` function to log all active bindings to the serial console.
- Output includes the **Node ID** (unique device address), **Remote Endpoint**, and **Cluster ID** (e.g., `0x0006` for OnOff).
- Example console output:
  ```text
  [TBR] Current bindings for endpoint 1:
    1. Node 0x0000000000001234 (Endpoint 1) for Cluster 0x00000006
  ```

## Thread Border Router Startup Sequence

```
1. app_main()
2. Matter.Node created, SwitchEndpoint + Binding cluster added
3. set_openthread_platform_config_native_shim() — configure 802.15.4 native radio
4. esp_matter::start() — Matter stack, Wi-Fi, BLE commissioning
5. Wi-Fi connects → init_openthread_border_router_shim():
   a. Set Wi-Fi STA as backbone netif
   b. Start border routing agent
   c. Enable SRP server + mDNS proxy
6. Button task + remote OnOff monitor started
7. Sleep forever (FreeRTOS tasks handle everything)
```

## Swift ↔ C++ Bridging

The C++ ESP-Matter SDK doesn't import cleanly into Swift due to type mismatches (`uint32_t` → `UInt` vs `CUnsignedLong`). The `MatterInterface/` directory provides thin C++ shims:

### Matter Attribute Shims

| Function | Purpose |
|----------|---------|
| `set_callback_shim` | Attribute change callbacks with Swift-compatible types |
| `get_shim` | Cluster/attribute lookup |
| `update_shim` | Attribute value updates |
| `report_shim` | Attribute reporting to fabric |
| `get_val_shim` | Attribute value retrieval |

### FreeRTOS Shims

FreeRTOS macros are not visible to Swift — these `extern "C"` wrappers are provided:

| Swift Function | Wraps |
|---|---|
| `ulTaskNotifyTake_shim(clearOnExit, ticks)` | `ulTaskNotifyTake` — block until notified |
| `vTaskNotifyGiveFromISR_shim(handle, &woken)` | `vTaskNotifyGiveFromISR` — notify from ISR |
| `portYIELD_FROM_ISR_shim(woken)` | `portYIELD_FROM_ISR` — context switch if needed |
| `xTaskCreate_shim(fn, name, stack, arg, prio)` | `xTaskCreate` — create a FreeRTOS task |
| `vTaskDelay_ms_shim(ms)` | `vTaskDelay(pdMS_TO_TICKS(ms))` |

### OpenThread Border Router Shims

| Function | Purpose |
|----------|---------|
| `set_openthread_platform_config_native_shim()` | Configure 802.15.4 native radio mode |
| `init_openthread_border_router_shim()` | Start border routing, SRP server, mDNS proxy (idempotent) |
| `create_thread_border_router_endpoint_shim(node)` | Create TBR Matter endpoint with PAN change feature |
| `init_client_callbacks_shim(id, cb, ctx)` | Register binding handler for remote OnOff subscription |
| `print_bindings_shim(id)` | Print all current bindings for an endpoint to the console |
| `subscribe_to_bound_devices_shim()` | Manually trigger subscription to all bound devices |

## License

This project is released under the [Creative Commons Zero (CC0 1.0 Universal)](https://creativecommons.org/publicdomain/zero/1.0/) license. You can copy, modify, distribute and perform the work, even for commercial purposes, all without asking permission.
