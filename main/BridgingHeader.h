//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

// FreeRTOS
// ==================================================

#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>

// Device drivers
// ==================================================

#include <driver/gpio.h>
#include <driver/spi_master.h>
#include <nvs_flash.h>
#include <sdkconfig.h>

// ESP-IDF core
// ==================================================

#include <esp_err.h>
#include <esp_log.h>
#include <esp_rom_sys.h>
#include <esp_timer.h>

// WiFi & Networking
// ==================================================

#include <esp_wifi.h>
#include <esp_event.h>
#include <esp_netif.h>
#include <esp_http_client.h>

// Shims
// ==================================================

#include "../MatterInterface/MatterInterface.h"

// --- Matter/CHIP headers (commented out, waiting for 8MB flash) ---
// #define CHIP_HAVE_CONFIG_H 1
// #define CHIP_USE_ENUM_CLASS_FOR_IM_ENUM 1
// #define CHIP_ADDRESS_RESOLVE_IMPL_INCLUDE_HEADER \
//     <lib/address_resolve/AddressResolve_DefaultImpl.h>
// extern "C" size_t strnlen(const char *s, size_t maxlen);
// extern "C" char *strdup(const char *s1);
// #include <esp_matter.h>
// #include <app-common/zap-generated/ids/Attributes.h>
// #include <app-common/zap-generated/ids/Clusters.h>
// #include <app/server/Server.h>
// #include <platform/CHIPDeviceLayer.h>
// #include <system/SystemClock.h>
