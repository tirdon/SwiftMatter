//===----------------------------------------------------------------------===//
//
// MatterInterface.cpp
// Core Matter attribute/cluster shims, fabric utilities, FreeRTOS helpers,
// and SPI master shims.
//
//===----------------------------------------------------------------------===//

#include "BridgingHeader.h"
#include "driver/spi_master.h"
#include "esp_err.h"
#include "esp_matter_core.h"
#include "portmacro.h"
#include <esp_netif.h>
#include <inttypes.h>

// =======================================================================
// MARK: - OpenThread (unused — native 802.15.4 configured elsewhere)
// =======================================================================

// #include <esp_openthread_types.h>
// #include <platform/ESP32/OpenthreadLauncher.h>
//
// static esp_openthread_platform_config_t s_ot_config = {
//     .radio_config = {.radio_mode = RADIO_MODE_NATIVE},
//     .host_config = {.host_connection_mode = HOST_CONNECTION_MODE_NONE},
//     .port_config = {.storage_partition_name = "nvs",
//                     .netif_queue_size = 10,
//                     .task_queue_size = 10},
// };
//
// void set_openthread_platform_config_native_shim() {
//   set_openthread_platform_config(&s_ot_config);
// }

// =======================================================================
// MARK: - Matter Attribute / Cluster Shims
// =======================================================================

esp_err_t esp_matter::attribute::set_callback_shim(callback_t_shim callback) {
  return set_callback((callback_t)callback);
}

esp_matter::cluster_t *
esp_matter::cluster::get_shim(esp_matter::endpoint_t *endpoint,
                              unsigned int cluster_id) {
  return get(endpoint, (uint32_t)cluster_id);
}

esp_matter::attribute_t *
esp_matter::attribute::get_shim(esp_matter::cluster_t *cluster,
                                unsigned int attribute_id) {
  return get(cluster, (uint32_t)attribute_id);
}

esp_err_t esp_matter::attribute::get_val_shim(unsigned short endpoint_id,
                                              unsigned int cluster_id,
                                              unsigned int attribute_id,
                                              esp_matter_attr_val_t *val) {
  return get_val(endpoint_id, (uint32_t)cluster_id, (uint32_t)attribute_id,
                 (esp_matter_attr_val_t *)val);
}

esp_err_t esp_matter::attribute::update_shim(uint16_t endpoint_id,
                                             unsigned int cluster_id,
                                             unsigned int attribute_id,
                                             esp_matter_attr_val_t *val) {
  return update(endpoint_id, (uint32_t)cluster_id, (uint32_t)attribute_id, val);
}

esp_err_t esp_matter::attribute::report_shim(unsigned short endpoint_id,
                                             unsigned int cluster_id,
                                             unsigned int attribute_id,
                                             esp_matter_attr_val_t *val) {
  return report((uint16_t)endpoint_id, (uint32_t)cluster_id,
                (uint32_t)attribute_id, (esp_matter_attr_val_t *)val);
}

// =======================================================================
// MARK: - Fabric / Network Utilities
// =======================================================================

void printStationIP() {
  esp_netif_ip_info_t ip_info;
  esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (netif && esp_netif_get_ip_info(netif, &ip_info) == ESP_OK) {
    printf("IP address: " IPSTR "\n", IP2STR(&ip_info.ip));
  }
}

void printFabricInfo() {
  if (!esp_matter::is_started()) {
    printf("Fabric info unavailable: Matter not started yet\n");
    return;
  }

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  const auto &fabricTable = chip::Server::GetInstance().GetFabricTable();
  printf("Fabric count: %u\n", fabricTable.FabricCount());
  for (const auto &fabricInfo : fabricTable) {
    printf("    Fabric index: %u\n", fabricInfo.GetFabricIndex());
    printf("\tFabric ID: 0x%" PRIx64 "\n", fabricInfo.GetFabricId());
    printf("\tCompressed Fabric ID: 0x%" PRIx64 "\n",
           fabricInfo.GetCompressedFabricId());
    printf("\tNode ID: 0x%" PRIx64 "\n", fabricInfo.GetNodeId());
    printf("\tVendor ID: 0x%04x\n", fabricInfo.GetVendorId());
  }
}

void recommissionFabric() {
  if (!esp_matter::is_started()) {
    printf("Cannot reopen commissioning window: Matter not started yet\n");
    return;
  }

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  if (chip::Server::GetInstance().GetFabricTable().FabricCount() == 0) {
    chip::CommissioningWindowManager &commissionMgr =
        chip::Server::GetInstance().GetCommissioningWindowManager();
    constexpr auto kTimeoutSeconds = chip::System::Clock::Seconds16(300);
    if (!commissionMgr.IsCommissioningWindowOpen()) {
      commissionMgr.OpenBasicCommissioningWindow(
          kTimeoutSeconds, chip::CommissioningWindowAdvertisement::kDnssdOnly);
    }
  }
}

// =======================================================================
// MARK: - FreeRTOS Task Notification Shims (for Swift)
// =======================================================================

extern "C" {

uint32_t ulTaskNotifyTake_shim(int32_t xClearCountOnExit,
                               uint32_t xTicksToWait) {
  return ulTaskNotifyTake((BaseType_t)xClearCountOnExit,
                          (TickType_t)xTicksToWait);
}

void vTaskNotifyGiveFromISR_shim(TaskHandle_t xTaskToNotify,
                                 int32_t *pxHigherPriorityTaskWoken) {
  vTaskNotifyGiveFromISR(xTaskToNotify,
                         (BaseType_t *)pxHigherPriorityTaskWoken);
}

void portYIELD_FROM_ISR_shim(int32_t xHigherPriorityTaskWoken) {
  if (xHigherPriorityTaskWoken) {
    portYIELD_FROM_ISR();
  }
}

void xTaskNotifyGive_shim(TaskHandle_t xTaskToNotify) {
  xTaskNotifyGive(xTaskToNotify);
}

} // extern "C"

// =======================================================================
// MARK: - SPI Master Shims
// =======================================================================

esp_err_t spi_bus_init_shim(int32_t host, int32_t mosi_pin, int32_t miso_pin,
                            int32_t sclk_pin, int32_t max_transfer_sz) {
  spi_bus_config_t bus_cfg = {};
  bus_cfg.mosi_io_num = mosi_pin;
  bus_cfg.miso_io_num = miso_pin;
  bus_cfg.sclk_io_num = sclk_pin;
  bus_cfg.quadwp_io_num = -1;
  bus_cfg.quadhd_io_num = -1;
  bus_cfg.max_transfer_sz = max_transfer_sz;
  return spi_bus_initialize((spi_host_device_t)host, &bus_cfg, SPI_DMA_CH_AUTO);
}

esp_err_t spi_add_device_shim(int32_t host, int32_t cs_pin,
                              int32_t clock_speed_hz, int32_t mode,
                              int32_t queue_size, void **out_handle) {
  spi_device_interface_config_t dev_cfg = {};
  dev_cfg.clock_speed_hz = clock_speed_hz;
  dev_cfg.mode = mode;
  dev_cfg.spics_io_num = cs_pin;
  dev_cfg.queue_size = queue_size;
  return spi_bus_add_device((spi_host_device_t)host, &dev_cfg,
                            (spi_device_handle_t *)out_handle);
}

esp_err_t spi_transfer_shim(void *handle, const uint8_t *tx_data,
                            uint8_t *rx_data, size_t length) {
  spi_transaction_t trans = {};
  trans.length = length * 8; // length in bits
  trans.tx_buffer = tx_data;
  trans.rx_buffer = rx_data;
  return spi_device_transmit((spi_device_handle_t)handle, &trans);
}

esp_err_t spi_remove_device_shim(void *handle) {
  return spi_bus_remove_device((spi_device_handle_t)handle);
}

esp_err_t spi_bus_free_shim(int32_t host) {
  return spi_bus_free((spi_host_device_t)host);
}
