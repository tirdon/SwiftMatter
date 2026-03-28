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

// GNU C++ interfaces do not work well with Swift for certain types, so let's
// use some simple C++ shims. For example, uint32_t gets imported as UInt and
// not CUnsignedLong (as defined in ESP IDF).

#include "esp_err.h"
#include "esp_matter_attribute_utils.h"
#include "esp_matter_data_model.h"
namespace esp_matter {
namespace attribute {
typedef esp_err_t (*callback_t_shim)(callback_type_t type, uint16_t endpoint_id,
                                     unsigned int cluster_id,
                                     unsigned int attribute_id,
                                     esp_matter_attr_val_t *val,
                                     void *priv_data);
esp_err_t set_callback_shim(callback_t_shim callback);
} // namespace attribute

namespace cluster {
cluster_t *get_shim(endpoint_t *endpoint, unsigned int cluster_id);
}

namespace attribute {
attribute_t *get_shim(cluster_t *cluster, unsigned int attribute_id);
esp_err_t get_val_shim(unsigned short endpoint_id, unsigned int cluster_id,
                       unsigned int attribute_id, esp_matter_attr_val_t *val);
esp_err_t report_shim(unsigned short endpoint_id, unsigned int cluster_id,
                      unsigned int attribute_id, esp_matter_attr_val_t *val);
} // namespace attribute

} // namespace esp_matter

#ifdef __cplusplus
extern "C" {
#endif

namespace esp_matter {
namespace attribute {
esp_err_t update_shim(uint16_t endpoint_id, unsigned int cluster_id,
                      unsigned int attribute_id, esp_matter_attr_val_t *val);
}
} // namespace esp_matter

#ifdef __cplusplus
}
#endif

// Recomissioning causes failures with reference semantics so this is done as a
// function implemented in C++. Ideally this would be done by changing some of
// the headers in ESP Matter to have proper Swift annotations.
void printStationIP();
void printFabricInfo();
void recomissionFabric();

// FreeRTOS task notification shims (macros not visible to Swift)
#ifdef __cplusplus
extern "C" {
#endif

uint32_t ulTaskNotifyTake_shim(int32_t xClearCountOnExit,
                               uint32_t xTicksToWait);
void vTaskNotifyGiveFromISR_shim(TaskHandle_t xTaskToNotify,
                                 int32_t *pxHigherPriorityTaskWoken);
void portYIELD_FROM_ISR_shim(int32_t xHigherPriorityTaskWoken);
void ulTaskNotifyGive_shim(TaskHandle_t xTaskToNotify);

// Crash recovery and heap monitoring shims
void esp_restart_shim(void);
uint32_t get_free_heap_size_shim(void);
uint32_t get_min_free_heap_size_shim(void);

// OpenThread Border Router shims
void set_openthread_platform_config_native_shim(void);
void init_openthread_border_router_shim(void);

// Create a Thread Border Router endpoint on the Matter node.
// Returns the endpoint_t pointer (opaque to Swift, used by esp_matter).
// Must be called before esp_matter::start().
void *create_thread_border_router_endpoint_shim(void *node);

// Remote on/off monitoring via binding + subscription.
// When a Matter controller binds this device's endpoint to a remote
// Thread device, the TBR auto-subscribes to the remote OnOff cluster.
// cb fires on every state change; ctx is forwarded as-is.
typedef void (*remote_onoff_cb_t)(bool on_off, void *ctx);
esp_err_t init_remote_onoff_monitor_shim(remote_onoff_cb_t cb, void *ctx);

#ifdef __cplusplus
}
#endif
