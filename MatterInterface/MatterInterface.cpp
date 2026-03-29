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
#include <app/OperationalSessionSetup.h>
#include <app/ReadClient.h>
#include <esp_heap_caps.h>
#include <app/clusters/bindings/binding-table.h>
#include <esp_matter_client.h>
#include <esp_netif.h>
#include <esp_system.h>
#include <inttypes.h>

// OpenThread Border Router headers
#include <esp_matter_feature.h>
#include <esp_openthread_border_router.h>
#include <esp_openthread_lock.h>
#include <esp_openthread_types.h>
#include <platform/ESP32/OpenthreadLauncher.h>
#include <platform/KvsPersistentStorageDelegate.h>
#include <platform/OpenThread/GenericThreadBorderRouterDelegate.h>

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
    printf("    Fabric index: %u\n", fabricInfo.GetFabricIndex());
    printf("\tFabric ID: 0x%" PRIx64 "\n", fabricInfo.GetFabricId());
    printf("\tCompressed Fabric ID: 0x%" PRIx64 "\n",
           fabricInfo.GetCompressedFabricId());
    printf("\tNode ID: 0x%" PRIx64 "\n", fabricInfo.GetNodeId());
    printf("\tVendor ID: 0x%04x\n", fabricInfo.GetVendorId());
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

void xTaskNotifyGive_shim(TaskHandle_t xTaskToNotify) {
  xTaskNotifyGive(xTaskToNotify);
}

void esp_restart_shim() { esp_restart(); }

uint32_t get_free_heap_size_shim() { return esp_get_free_heap_size(); }

uint32_t get_min_free_heap_size_shim() {
  return esp_get_minimum_free_heap_size();
}

// ── Generic FreeRTOS shims (macros not visible to Swift) ────────────────

void xTaskCreate_shim(void (*task)(void *), const char *name, uint32_t stack,
                      void *arg, uint32_t prio) {
  xTaskCreate(task, name, stack, arg, prio, NULL);
}

void vTaskDelay_ms_shim(uint32_t ms) { vTaskDelay(pdMS_TO_TICKS(ms)); }

// ── OpenThread Border Router shims ──────────────────────────────────────

static bool s_br_initialized = false;

void set_openthread_platform_config_native_shim(void) {
  esp_openthread_platform_config_t config = {};
  config.radio_config.radio_mode = RADIO_MODE_NATIVE;
  config.host_config.host_connection_mode = HOST_CONNECTION_MODE_NONE;
  config.port_config.storage_partition_name = "nvs";
  config.port_config.netif_queue_size = 10;
  config.port_config.task_queue_size = 10;
  set_openthread_platform_config(&config);
  printf("[TBR] OpenThread platform config set (native radio)\n");
}

void init_openthread_border_router_shim(void) {
  if (s_br_initialized)
    return;
  esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (!netif) {
    printf("[TBR] WiFi STA netif not found, deferring BR init\n");
    return;
  }
  esp_openthread_lock_acquire(portMAX_DELAY);
  esp_openthread_set_backbone_netif(netif);
  esp_openthread_border_router_init();
  esp_openthread_lock_release();
  s_br_initialized = true;
  printf("[TBR] Border router initialized (WiFi backbone)\n");
}

void *create_thread_border_router_endpoint_shim(void *node) {
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  using namespace chip::app::Clusters;
  using GenericDelegate =
      ThreadBorderRouterManagement::GenericOpenThreadBorderRouterDelegate;

  // KVS storage delegate for the TBR delegate's persistent state
  static chip::KvsPersistentStorageDelegate s_tbr_storage;
  auto &kvsMgr = chip::DeviceLayer::PersistedStorage::KeyValueStoreMgr();
  s_tbr_storage.Init(&kvsMgr);

  auto *delegate = chip::Platform::New<GenericDelegate>(&s_tbr_storage);
  if (!delegate) {
    printf("[TBR] Failed to create TBR delegate\n");
    return nullptr;
  }
  char name[] = "ESP32-C6 Thread BR";
  delegate->SetThreadBorderRouterName(chip::CharSpan(name));

  esp_matter::endpoint::thread_border_router::config_t tbr_config;
  tbr_config.thread_border_router_management.delegate = delegate;
  auto *ep = esp_matter::endpoint::thread_border_router::create(
      static_cast<esp_matter::node_t *>(node), &tbr_config,
      esp_matter::ENDPOINT_FLAG_NONE, nullptr);
  if (!ep) {
    printf("[TBR] Failed to create TBR endpoint\n");
    return nullptr;
  }

  // Enable PAN change feature
  auto *cluster =
      esp_matter::cluster::get(ep, ThreadBorderRouterManagement::Id);
  if (cluster) {
    esp_matter::cluster::thread_border_router_management::feature::pan_change::
        add(cluster);
  }

  printf("[TBR] Thread Border Router endpoint created (id=%u)\n",
         esp_matter::endpoint::get_id(ep));
  return ep;
}

} // extern "C"

// ---------------------------------------------------------------------------
// Client request callbacks — invoke + subscribe to bound devices
// ---------------------------------------------------------------------------

static remote_onoff_cb_t s_remote_onoff_cb = nullptr;
static void *s_remote_onoff_ctx = nullptr;
static uint16_t s_local_endpoint_id = 0;
static bool s_subscribed = false;

// ReadClient::Callback that decodes OnOff attribute reports from the
// subscribed remote device and forwards them to the Swift callback.
class OnOffSubscriptionCallback : public chip::app::ReadClient::Callback {
public:
  void OnAttributeData(const chip::app::ConcreteDataAttributePath &path,
                       chip::TLV::TLVReader *data,
                       const chip::app::StatusIB &status) override {
    if (!s_remote_onoff_cb || !data)
      return;
    if (path.mClusterId != chip::app::Clusters::OnOff::Id)
      return;
    if (path.mAttributeId != chip::app::Clusters::OnOff::Attributes::OnOff::Id)
      return;

    bool val = false;
    if (data->Get(val) == CHIP_NO_ERROR) {
      s_remote_onoff_cb(val, s_remote_onoff_ctx);
    }
  }

  void OnError(CHIP_ERROR error) override {
    printf("[TBR] OnOff subscription error\n");
  }

  void OnDone(chip::app::ReadClient *client) override {
    printf("[TBR] OnOff subscription ended\n");
  }

  void OnSubscriptionEstablished(chip::SubscriptionId id) override {
    printf("[TBR] OnOff subscription established (id=%u)\n", (unsigned)id);
  }
};

static OnOffSubscriptionCallback s_onoff_sub_cb;

// Unicast request callback — called by esp_matter binding manager after CASE
// session is established. Dispatches invoke or subscribe depending on type.
static void on_client_request(esp_matter::client::peer_device_t *peer_device,
                              esp_matter::client::request_handle_t *req_handle,
                              void *priv_data) {
  if (req_handle->type == esp_matter::client::INVOKE_CMD) {
    esp_matter::client::interaction::invoke::send_request(
        NULL, peer_device, req_handle->command_path, "{}",
        [](void *, const chip::app::ConcreteCommandPath &,
           const chip::app::StatusIB &,
           chip::TLV::TLVReader *) { printf("[TBR] Toggle sent OK\n"); },
        [](void *, CHIP_ERROR) { printf("[TBR] Toggle send failed\n"); },
        chip::NullOptional);
  } else if (req_handle->type == esp_matter::client::SUBSCRIBE_ATTR) {
    esp_matter::client::interaction::subscribe::send_request(
        peer_device, &req_handle->attribute_path, 1, nullptr, 0, 1, 30, true,
        true, s_onoff_sub_cb);
    printf("[TBR] Subscribed to remote OnOff\n");
  }
}

// Group request callback — sends group commands for multicast bindings.
static void on_group_request(uint8_t fabric_index,
                             esp_matter::client::request_handle_t *req_handle,
                             void *priv_data) {
  if (req_handle->type != esp_matter::client::INVOKE_CMD)
    return;
  esp_matter::client::interaction::invoke::send_group_request(
      fabric_index, req_handle->command_path, "{}");
  printf("[TBR] Group toggle sent\n");
}

extern "C" void init_client_callbacks_shim(uint16_t endpoint_id,
                                           remote_onoff_cb_t cb, void *ctx) {
  s_local_endpoint_id = endpoint_id;
  s_remote_onoff_cb = cb;
  s_remote_onoff_ctx = ctx;
  esp_matter::client::set_request_callback(on_client_request, on_group_request,
                                           NULL);
  printf("[TBR] Client callbacks initialized (endpoint %u)\n", endpoint_id);
}

extern "C" void print_bindings_shim(uint16_t endpoint_id) {
  using namespace chip::app::Clusters::Binding;
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  auto &bindingTable = Table::GetInstance();
  printf("[TBR] Current bindings for endpoint %u:\n", endpoint_id);
  int count = 0;
  for (auto &entry : bindingTable) {
    if (entry.local == endpoint_id) {
      count++;
      if (entry.type == MATTER_UNICAST_BINDING) {
        printf("  %d. Node 0x%016llX (Endpoint %u) for Cluster 0x%08lX\n",
               count, entry.nodeId, entry.remote, entry.clusterId.value_or(0));
      } else if (entry.type == MATTER_MULTICAST_BINDING) {
        printf("  %d. Group ID %u for Cluster 0x%08lX\n", count, entry.groupId,
               entry.clusterId.value_or(0));
      }
    }
  }
  if (count == 0) {
    printf("  (none)\n");
  }
}

extern "C" void send_bound_toggle_shim(uint16_t endpoint_id) {
  esp_matter::client::request_handle_t req_handle;
  req_handle.type = esp_matter::client::INVOKE_CMD;
  req_handle.command_path.mClusterId = chip::app::Clusters::OnOff::Id;
  req_handle.command_path.mCommandId =
      chip::app::Clusters::OnOff::Commands::Toggle::Id;

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  esp_err_t err = esp_matter::client::cluster_update(endpoint_id, &req_handle);
  if (err != ESP_OK) {
    printf("[TBR] send_bound_toggle failed: 0x%x\n", err);
  }
}

extern "C" void subscribe_to_bound_devices_shim(void) {
  if (s_local_endpoint_id == 0)
    return;
  s_subscribed = false;

  esp_matter::client::request_handle_t req_handle;
  req_handle.type = esp_matter::client::SUBSCRIBE_ATTR;
  req_handle.attribute_path.mClusterId = chip::app::Clusters::OnOff::Id;
  req_handle.attribute_path.mAttributeId =
      chip::app::Clusters::OnOff::Attributes::OnOff::Id;

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  esp_err_t err =
      esp_matter::client::cluster_update(s_local_endpoint_id, &req_handle);
  if (err == ESP_OK) {
    s_subscribed = true;
    printf("[TBR] Subscription request sent to bound devices\n");
  } else {
    printf("[TBR] subscribe_to_bound failed: 0x%x\n", err);
  }
}