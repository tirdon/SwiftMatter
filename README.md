# SwiftMatter Template

This branch is a template for building an ESP32-C3/C6 Matter device in Embedded Swift with ESP-Matter. It starts from a working on/off accessory and shows where to add LEDs, buttons, sensors, and other Matter endpoints.

## What This Template Includes

- Embedded Swift app entry point wired into ESP-IDF
- Matter root node, endpoint, and attribute bridging in Swift
- Button and LED device helpers
- Example commissioning, binding, and ACL commands for multi-device setups

## Repository Layout

```
Irrigation/
├── CMakeLists.txt              # Top-level ESP-IDF and ESP-Matter build config
├── partitions.csv              # Flash layout for app, OTA, NVS, and coredump
├── sdkconfig.defaults          # Default Matter configuration
├── main/
│   ├── CMakeLists.txt          # Swift source list and compiler flags for the app
│   ├── BridgingHeader.h        # C/C++ headers imported into Swift
│   ├── linker.lf               # Linker script for the app
│   ├── Main.swift              # app_main entry point and boot sequence
│   ├── PhysicalDevices.swift   # Board-specific GPIO, sensors, and helper logic
│   └── SwitchEndpoint.swift    # Matter endpoint template for the switch device
└── MatterInterface/
    ├── Core.swift              # Core Matter abstractions for nodes, endpoints, clusters
    ├── Core+ID.swift           # Typed cluster and attribute IDs
    ├── Core+RootNode.swift     # Concrete Swift wrappers for the Matter data model
    ├── Matter.swift            # High-level application-facing Matter types
    ├── Matter+Application.swift # Matter startup and device event handling
    ├── Matter+OnBoardLED.swift # Status LED helper tied to Wi-Fi state
    ├── MatterInterface.cpp     # C++ shims that normalize ESP-Matter APIs for Swift
    └── MatterInterface.h       # C++ declarations consumed by the Swift bridge
```

## Hardware Defaults

These are the defaults used in this branch. Change them to match your board:

| Component | GPIO | Notes |
|-----------|------|-------|
| Relay / External LED | 9 | Active high |
| Onboard Status LED | 8 | Active low |
| Push Button | 21 | Active high |

## Prerequisites

- ESP-IDF v5.4.1 or newer
- ESP-Matter v1.5 SDK
- Swift toolchain 6.0 or newer with Embedded Swift support
- CMake 3.29 or newer

## Build And Flash

Setting Wi-Fi credentials into [`sdkconfig.defaults`](./sdkconfig.defaults), add:

```text
CONFIG_DEFAULT_WIFI_SSID="<your wifi ssid>"
CONFIG_DEFAULT_WIFI_PASSWORD="<your wifi password>"
```

```bash
export TOOLCHAINS=org.swift.<toolchain-id>
export IDF_PATH=<path to esp-idf>
export ESP_MATTER_PATH=<path to esp-matter>

source $IDF_PATH/export.sh
source $ESP_MATTER_PATH/export.sh

idf.py set-target esp32c3
idf.py build
idf.py -p /dev/tty.usbserial-* flash monitor
```

## Customize This Template

1. Update the device name in `main/Main.swift`.
2. Adjust GPIOs in `main/PhysicalDevices.swift`.
3. Add or remove endpoints in `main/SwitchEndpoint.swift`.
4. Extend the Matter model in `MatterInterface/` if you need new clusters or attributes.
5. Tune `sdkconfig.defaults` and `partitions.csv` for your board and OTA strategy.

## Commissioning

After flashing, the device advertises over BLE for Matter commissioning.

```bash
chip-tool pairing ble-wifi <node-id> <ssid> <password> <setup-pin-code> <discriminator>
```

```bash
chip-tool pairing code <node-id> <setup-code>
```

## Example Multi-Device Setup

Use this when one device acts as the controller and another device acts as the controlled accessory.

### Write the Binding Entry on the Controlling Device

This tells the switch which device and endpoint to control.

```bash
chip-tool binding write binding '[{"node" : 1 , "cluster" : 6 , "endpoint" : 1}]' 2 1
```

- `node`: Target Node ID, for example `1` for the light bulb.
- `cluster`: Cluster ID to control, for example `6` for On/Off.
- `endpoint`: Target endpoint on the controlled device, usually `1`.
- `2`: Node ID of the controlling device, for example the switch.
- `1`: Endpoint ID on the controlling device.

### Write the Access Control List on the Controlled Device

This grants the controlling device permission to send unicast commands to the controlled device.

```bash
chip-tool accesscontrol write acl '[{"privilege": 3, "authMode": 2, "subjects": [2], "targets": [{"cluster": 6, "endpoint": 1}]}]' 1 0
```

- `privilege`: `3` grants `Operate`.
- `authMode`: `2` selects CASE.
- `subjects`: `[2]` is the controlling device Node ID.
- `targets`: The cluster and endpoint the controller may access.
- `1`: Node ID of the controlled device.
- `0`: Endpoint ID of the Access Control cluster, usually endpoint 0 root_node.

## Notes

- The root node already includes Access Control through ESP-Matter.
- `MatterInterface/` exists to smooth over Swift and ESP-Matter type mismatches.
- Optional sensor blocks in `PhysicalDevices.swift` can be enabled as needed for your hardware.

## License

This project is released under the Unlicense. See [`LICENSE`](./LICENSE) for the full text.
