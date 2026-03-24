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

#include "BridgingHeader.h"
#include "esp_err.h"
#include "esp_matter_attribute_utils.h"
#include "portmacro.h"
#include <inttypes.h>
#include <esp_netif.h>
#include <esp_system.h>
#include <esp_heap_caps.h>

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

void printStationIP() {
  esp_netif_ip_info_t ip_info;
  esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (netif && esp_netif_get_ip_info(netif, &ip_info) == ESP_OK) {
    printf("IP address: " IPSTR "\n", IP2STR(&ip_info.ip));
  }
}

void printFabricInfo() {
  const auto &fabricTable = chip::Server::GetInstance().GetFabricTable();
  printf("Fabric count: %u\n", fabricTable.FabricCount());
  for (const auto &fabricInfo : fabricTable) {
    printf("  Fabric index: %u\n", fabricInfo.GetFabricIndex());
    printf("    Fabric ID: 0x%" PRIx64 "\n", fabricInfo.GetFabricId());
    printf("    Compressed Fabric ID: 0x%" PRIx64 "\n",
           fabricInfo.GetCompressedFabricId());
    printf("    Node ID: 0x%" PRIx64 "\n", fabricInfo.GetNodeId());
    printf("    Vendor ID: 0x%04x\n", fabricInfo.GetVendorId());
  }
}

void recomissionFabric() {
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

// FreeRTOS task notification shims for Swift
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


void ulTaskNotifyGive_shim(TaskHandle_t xTaskToNotify) {
  xTaskNotifyGive(xTaskToNotify);
}

void esp_restart_shim() {
  esp_restart();
}

uint32_t get_free_heap_size_shim() {
  return esp_get_free_heap_size();
}

uint32_t get_min_free_heap_size_shim() {
  return esp_get_minimum_free_heap_size();
}
}