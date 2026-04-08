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
} // namespace attribute

namespace client {
esp_err_t cluster_update_shim(uint16_t endpoint_id, request_handle_t *req);

esp_err_t init_client_callbacks_shim();
void subscribe_to_bound_device_shim(uint16_t remote_endpoint_id,
                                     uint64_t node_id, uint8_t fabric_index);
void subscribe_to_all_bound_devices_shim(uint16_t local_endpoint_id);
void read_bound_device_onoff_shim(uint16_t local_endpoint_id);
void print_bindings_shim(uint16_t endpoint_id);
} // namespace client
} // namespace esp_matter

void update_local_led_shim(bool state);

void printStationIP();
void printFabricInfo();
void recommissionFabric();

uint32_t ulTaskNotifyTake_shim(int32_t xClearCountOnExit,
                               uint32_t xTicksToWait);
void vTaskNotifyGiveFromISR_shim(TaskHandle_t xTaskToNotify,
                                 int32_t *pxHigherPriorityTaskWoken);
void portYIELD_FROM_ISR_shim(int32_t xHigherPriorityTaskWoken);
void xTaskNotifyGive_shim(TaskHandle_t xTaskToNotify);

// SPI master shims
esp_err_t spi_bus_init_shim(int32_t host, int32_t mosi_pin, int32_t miso_pin,
                            int32_t sclk_pin, int32_t max_transfer_sz);
esp_err_t spi_add_device_shim(int32_t host, int32_t cs_pin,
                              int32_t clock_speed_hz, int32_t mode,
                              int32_t queue_size, void **out_handle);
esp_err_t spi_transfer_shim(void *handle, const uint8_t *tx_data,
                            uint8_t *rx_data, size_t length);
esp_err_t spi_remove_device_shim(void *handle);
esp_err_t spi_bus_free_shim(int32_t host);

// void set_openthread_platform_config_native_shim();

void on_server_update(esp_matter::client::peer_device_t *peer_device,
                      esp_matter::client::request_handle_t *req_handle,
                      void *priv_data);

void on_group_request(uint8_t fabric_index,
                      esp_matter::client::request_handle_t *req_handle,
                      void *priv_data);

#ifdef __cplusplus
}
#endif
