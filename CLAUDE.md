# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESP32-C3/C6 irrigation controller written in **Embedded Swift**, using the Matter smart home protocol via Espressif's ESP-Matter SDK. Exposes Matter endpoints for relay control, DHT22 temp/humidity, DS18B20 waterproof temperature, and capacitive soil moisture — controllable from Apple Home, Google Home, or any Matter-compatible app.

## Build Commands

```bash
# Required environment setup (must be done each shell session)
export TOOLCHAINS=org.swift.<version>
export IDF_PATH=<path>/esp-idf
export ESP_MATTER_PATH=<path>/esp-matter
. $IDF_PATH/export.sh
. $ESP_MATTER_PATH/export.sh

# Set target chip
idf.py set-target esp32c3   # or esp32c6

# Build
idf.py build

# Flash and monitor (serial port varies)
idf.py -p /dev/tty.usbserial-* flash monitor

# Monitor only
idf.py -p /dev/tty.usbserial-* monitor

# Clean build
idf.py fullclean
```

There is no test infrastructure — this is a bare-metal embedded project. Verification is done by flashing and monitoring serial output.

## Architecture

**Language**: Embedded Swift (experimental) compiled to RISC-V bare metal (`riscv32-none-none-eabi`) with C++ interoperability mode for bridging to ESP-IDF/Matter C++ APIs.

### Two main components:

**`main/`** — Application logic:
- `Main.swift` — `@_cdecl("app_main")` entry point. Creates Matter node, registers endpoints, starts Matter application, then sleeps forever.
- `PhysicalDevices.swift` — Device drivers for LED, Button, DHT22, DS18B20, soil moisture sensor, IR receiver/transmitter. Sensors run as FreeRTOS tasks polling every 10s. IR uses GPIO ISR + `ulTaskNotifyTake` for low-power wake-on-signal.
- `SwitchEndpoint.swift` — Matter endpoint type definitions (on/off switch, temperature sensor, humidity sensor, dimmable light repurposed for moisture).

**`MatterInterface/`** — Swift/C++ bridging layer:
- `MatterInterface.h/.cpp` — `extern "C"` shim functions that wrap C++ ESP-Matter APIs and FreeRTOS macros (which Swift cannot import directly). Required because GNU C++ types don't map cleanly to Swift (e.g., `uint32_t` becomes `UInt` not `CUnsignedLong`).
- `Core.swift`, `Core+ID.swift`, `Core+RootNode.swift` — Swift protocol hierarchy (`MatterNode`/`MatterEndpoint`/`MatterCluster`/`MatterAttribute`) and typed ID wrappers providing type-safe access to Matter data model.
- `Matter.swift` — High-level `Matter.Node` with endpoint event routing from Matter callbacks.
- `Matter+Application.swift` — Matter stack startup, WiFi event callbacks, fabric management.
- `Matter+OnBoardLED.swift` — Status LED indicating WiFi connectivity.

### Data flow:
Sensor FreeRTOS tasks → read hardware → `report_shim()` → Matter fabric. Button press / IR command / Matter fabric command → `Matter.Node` event routing → LED/relay GPIO toggle.

## Key Technical Constraints

- **Embedded Swift** requires `-enable-experimental-feature Embedded -wmo` (whole module optimization). No Swift runtime, no reflection, no existentials.
- **C++ interop** is via `-cxx-interoperability-mode=default` with C++17. All C/C++ headers go through `BridgingHeader.h`.
- FreeRTOS macros (`ulTaskNotifyTake`, `vTaskNotifyGiveFromISR`, `portYIELD_FROM_ISR`) are not visible to Swift — use the `*_shim()` wrappers in `MatterInterface.h`.
- Task stack sizes are increased in `sdkconfig.defaults` (16 KB main, 16 KB Matter, 8 KB BLE) for Swift/Matter compatibility.
- The CMake project name is `light` (inherited from ESP-Matter example scaffolding).
- Supported targets: ESP32-C3 (`rv32imc`) and ESP32-C6 (`rv32imac`). Target-specific ISA flags are set in `main/CMakeLists.txt`.

## GPIO Assignments (current code, may differ from README)

Check `PhysicalDevices.swift` and `Matter+OnBoardLED.swift` for authoritative pin numbers — these change between branches/targets. The `esp32c6` branch currently uses GPIO 16 (LED), GPIO 17 (Button), GPIO 15 (status LED), GPIO 4 (DHT22), GPIO 0 (IR receiver).

## Adding a New Sensor

1. Add a device driver class in `PhysicalDevices.swift` with a FreeRTOS task for polling.
2. Define a new Matter endpoint type in `SwitchEndpoint.swift`.
3. Wire it up in `Main.swift` — create the endpoint on the Matter node, instantiate the driver.
4. If new C/C++ APIs are needed, add shim functions in `MatterInterface.h/.cpp` and include headers in `BridgingHeader.h`.
