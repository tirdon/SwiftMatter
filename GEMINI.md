# GEMINI.md — Project Context & Instructions

This document provides essential context and instructional mandates for AI interactions within the **SwiftMatter TBR** project.

## Project Overview

**SwiftMatter TBR** is an ESP32-C6 **Thread Border Router** (TBR) implementation that bridges a Thread mesh network (802.15.4) to a Wi-Fi/IP network using the **Matter** protocol.

- **Main Technologies:** Embedded Swift, ESP-IDF (v5.3+), ESP-Matter SDK, OpenThread.
- **Hardware Target:** ESP32-C6 (specifically chosen for its native 802.15.4 + Wi-Fi radios).
- **Architecture:**
    - **Logic Layer:** Written in **Embedded Swift** (`main/*.swift`, `MatterInterface/*.swift`).
    - **Interface Layer:** C++ shims (`MatterInterface/MatterInterface.cpp`) to bridge Swift and the ESP-Matter SDK (handling type mismatches like `uint32_t` vs `UInt`).
    - **Protocol Stack:** ESP-Matter for application layer, OpenThread for networking, ESP-IDF for hardware abstraction.
- **Key Features:** Matter over Wi-Fi, Thread Border Routing, On/Off Switch endpoint, and remote device monitoring via Matter Bindings.

## Building and Running

Ensure `IDF_PATH` and `ESP_MATTER_PATH` are exported in your environment.

```bash
# 1. Set the target to ESP32-C6 (mandatory for Thread)
idf.py set-target esp32c6

# 2. Build the project
idf.py build

# 3. Flash and monitor output
idf.py -p <PORT> flash monitor
```

- **Commissioning:** The device starts BLE advertising upon first boot. Use `chip-tool` or a Matter controller (Apple Home, Google Home).
- **Console Debugging:** Use `print_bindings_shim(endpoint_id)` to inspect active bindings.

## Development Conventions

### 1. Swift ↔ C++ Interop
- **Direct Imports:** Matter and ESP-IDF headers are imported via `main/BridgingHeader.h`.
- **Shims:** Because certain C types (like `uint32_t` or FreeRTOS macros) do not import cleanly into Swift, always check `MatterInterface/MatterInterface.h` for existing shims before creating new ones.
- **Memory Management:** Use `Unmanaged` when passing Swift object context to C callbacks (e.g., in `Matter+Application.swift`).

### 2. Matter Data Model
- **Abstractions:** Use the protocols in `MatterInterface/Core.swift` (`MatterNode`, `MatterEndpoint`, `MatterCluster`) to interact with the Matter data model.
- **Attribute Updates:** Use `update_shim` or `report_shim` to modify or notify the fabric of attribute changes.

### 3. Concurrency & Safety
- **Locking:** When calling Matter stack functions from C++, use `esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);`.
- **FreeRTOS:** Use the provided shims (e.g., `xTaskCreate_shim`, `vTaskDelay_ms_shim`) for task management in Swift.

### 4. Code Structure
- `main/`: Application-level Swift code and hardware-specific logic (LED, Button).
- `MatterInterface/`: High-level Matter abstractions (Swift) and low-level C++ shims.

## Key Identification & Debugging
- **Identifying Bound Devices:** Call `print_bindings_shim(1)` in the `kBindingsChangedViaCluster` event handler to see which remote devices have been bound to this device.
- **Remote Monitoring:** The system uses `init_client_callbacks_shim` and `subscribe_to_bound_devices_shim` to automatically track the state of bound OnOff devices.
