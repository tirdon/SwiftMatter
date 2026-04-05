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
#include "driver/spi_master.h"
#include "esp_err.h"
#include "esp_matter_client.h"
#include "esp_matter_core.h"
#include "portmacro.h"
#include <app/clusters/bindings/binding-table.h>
#include <cstdio>
#include <esp_heap_caps.h>
#include <esp_netif.h>
#include <esp_system.h>
#include <inttypes.h>

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

void recomissionFabric() {
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

void xTaskNotifyGive_shim(TaskHandle_t xTaskToNotify) {
  xTaskNotifyGive(xTaskToNotify);
}

esp_err_t esp_matter::client::cluster_update_shim(uint16_t endpoint_id,
                                                  request_handle_t *req) {
  if (!req) {
    return ESP_ERR_INVALID_ARG;
  }
  if (!esp_matter::is_started()) {
    printf("[LIGHT] Ignoring cluster update before Matter startup\n");
    return ESP_ERR_INVALID_STATE;
  }

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  return cluster_update(endpoint_id, req);
}

esp_err_t esp_matter::client::init_client_callbacks_shim() {
  return set_request_callback(on_server_update, on_group_request, nullptr);
}

void print_bindings_shim(uint16_t endpoint_id) {
  if (!esp_matter::is_started()) {
    printf("[TBR] Cannot print bindings before Matter start\n");
    return;
  }

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  auto &bindingTable = chip::app::Clusters::Binding::Table::GetInstance();
  printf("[TBR] Bindings for endpoint %d:\n", endpoint_id);
  for (const auto &entry : bindingTable) {
    if (entry.local == endpoint_id) {
      if (entry.type == chip::app::Clusters::Binding::MATTER_UNICAST_BINDING) {
        printf("  Unicast: NodeID: 0x%" PRIx64 ", Fabric: %d, Remote EP: %d\n",
               entry.nodeId, entry.fabricIndex, entry.remote);
      } else if (entry.type ==
                 chip::app::Clusters::Binding::MATTER_MULTICAST_BINDING) {
        printf("  Multicast: GroupID: 0x%04x, Fabric: %d\n", entry.groupId,
               entry.fabricIndex);
      }
    }
  }
}

} // extern "C"

// =======================================================================
// MARK: bind
// =======================================================================
namespace {
constexpr uint16_t kMinSubscribeIntervalSeconds = 5;
constexpr uint16_t kMaxSubscribeIntervalSeconds = 2 * 60;

bool is_onoff_attribute_path(const chip::app::AttributePathParams &path) {
  return path.mClusterId == chip::app::Clusters::OnOff::Id &&
         path.mAttributeId == chip::app::Clusters::OnOff::Attributes::OnOff::Id;
}

bool is_onoff_command_path(const chip::app::CommandPathParams &path) {
  return path.mClusterId == chip::app::Clusters::OnOff::Id;
}

void send_command_success_callback(void *context,
                                   const chip::app::ConcreteCommandPath &path,
                                   const chip::app::StatusIB &status,
                                   chip::TLV::TLVReader *response_data) {
  printf("[LIGHT] Command OK: cluster=0x%" PRIx32 " cmd=0x%" PRIx32 "\n",
         path.mClusterId, path.mCommandId);
}

void send_command_failure_callback(void *context, CHIP_ERROR error) {
  printf("[LIGHT] Command send failed: %" CHIP_ERROR_FORMAT "\n",
         error.Format());
}
} // namespace

class OnOffReadCallback : public chip::app::ReadClient::Callback {
public:
  void OnAttributeData(const chip::app::ConcreteDataAttributePath &path,
                       chip::TLV::TLVReader *data,
                       const chip::app::StatusIB &status) override {
    if (!data) {
      printf("[LIGHT] No data\n");
      return;
    }
    if (path.mClusterId != chip::app::Clusters::OnOff::Id) {
      printf("[LIGHT] Invalid cluster ID\n");
      return;
    }
    if (path.mAttributeId !=
        chip::app::Clusters::OnOff::Attributes::OnOff::Id) {
      printf("[LIGHT] Invalid attribute ID\n");
      return;
    }

    bool val = false;
    if (data->Get(val) == CHIP_NO_ERROR) {
      printf("[LIGHT] Bound device OnOff state: %s\n", val ? "ON" : "OFF");
      update_local_led_shim(val);
    }
  }

  void OnError(CHIP_ERROR error) override {
    printf("[LIGHT] OnOff read/subscribe error: %" CHIP_ERROR_FORMAT "\n",
           error.Format());
  }

  void OnDone(chip::app::ReadClient *client) override {
    printf("[LIGHT] OnOff read/subscribe ended\n");
  }

  void OnSubscriptionEstablished(chip::SubscriptionId id) override {
    printf("[LIGHT] OnOff subscription established (id=%u)\n", (unsigned)id);
  }
};

static OnOffReadCallback sOnOffReadCallback;

void on_server_update(esp_matter::client::peer_device_t *peer_device,
                      esp_matter::client::request_handle_t *req_handle,
                      void *priv_data) {
  printf("[LIGHT] on_server_update\n");
  if (!peer_device || !req_handle) {
    printf("[LIGHT] Invalid peer_device or req_handle\n");
    return;
  }

  if (req_handle->type == esp_matter::client::INVOKE_CMD) {
    if (!is_onoff_command_path(req_handle->command_path)) {
      printf("[LIGHT] Invalid command path\n");
      return;
    }

    esp_matter::client::interaction::invoke::send_request(
        nullptr, peer_device, req_handle->command_path, "{}",
        send_command_success_callback, send_command_failure_callback,
        chip::NullOptional, chip::NullOptional);

    return;
  }

  if (req_handle->type == esp_matter::client::READ_ATTR) {
    if (!is_onoff_attribute_path(req_handle->attribute_path)) {
      return;
    }

    esp_matter::client::interaction::read::send_request(
        peer_device, &req_handle->attribute_path, 1, nullptr, 0,
        sOnOffReadCallback);
    return;
  }

  if (req_handle->type == esp_matter::client::SUBSCRIBE_ATTR) {
    if (!is_onoff_attribute_path(req_handle->attribute_path)) {
      return;
    }

    esp_matter::client::interaction::subscribe::send_request(
        peer_device, &req_handle->attribute_path, 1, nullptr, 0,
        kMinSubscribeIntervalSeconds, kMaxSubscribeIntervalSeconds, true, true,
        sOnOffReadCallback);
    return;
  }
}

void on_group_request(uint8_t fabric_index,
                      esp_matter::client::request_handle_t *req_handle,
                      void *priv_data) {
  if (req_handle->type != esp_matter::client::INVOKE_CMD) {
    printf("[LIGHT] Invalid command path\n");
    return;
  }
  if (!is_onoff_command_path(req_handle->command_path)) {
    printf("[LIGHT] Invalid command path\n");
    return;
  }
  esp_matter::client::interaction::invoke::send_group_request(
      fabric_index, req_handle->command_path, "{}");
  printf("[LIGHT] Group toggle sent\n");
}

extern "C" void subscribe_to_bound_device_shim(uint16_t remote_endpoint_id,
                                                uint64_t node_id,
                                                uint8_t fabric_index) {
  if (!esp_matter::is_started()) {
    printf("[TBR] Skipping subscription before Matter start\n");
    return;
  }

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  esp_matter::client::request_handle_t req;
  req.type = esp_matter::client::SUBSCRIBE_ATTR;
  req.attribute_path = chip::app::AttributePathParams(
      remote_endpoint_id, chip::app::Clusters::OnOff::Id,
      chip::app::Clusters::OnOff::Attributes::OnOff::Id);

  esp_matter::client::connect(
      chip::Server::GetInstance().GetCASESessionManager(), fabric_index,
      node_id, &req);
  printf("[TBR] Subscribing to 0x%" PRIx64 " (Endpoint %d)\n", node_id,
         remote_endpoint_id);
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
    printf("  Fabric index: %u\n", fabricInfo.GetFabricIndex());
    printf("    Fabric ID: 0x%" PRIx64 "\n", fabricInfo.GetFabricId());
    printf("    Compressed Fabric ID: 0x%" PRIx64 "\n",
           fabricInfo.GetCompressedFabricId());
    printf("    Node ID: 0x%" PRIx64 "\n", fabricInfo.GetNodeId());
    printf("    Vendor ID: 0x%04x\n", fabricInfo.GetVendorId());
  }
}