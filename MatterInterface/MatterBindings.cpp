//===----------------------------------------------------------------------===//
//
// MatterBindings.cpp
// Matter client callbacks, binding/subscription management, and OnOff read logic.
//
//===----------------------------------------------------------------------===//

#include "BridgingHeader.h"
#include "esp_matter_client.h"
#include "esp_matter_core.h"
#include <app/clusters/bindings/binding-table.h>
#include <inttypes.h>

// =======================================================================
// MARK: - Helpers
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
chip::app::AttributePathParams
get_onoff_attribute_path(chip::EndpointId endpoint_id) {
  return chip::app::AttributePathParams(
      endpoint_id, chip::app::Clusters::OnOff::Id,
      chip::app::Clusters::OnOff::Attributes::OnOff::Id);
}

template <typename Action>
void do_for_unicast_bindings(uint16_t local_endpoint_id, Action &&action) {
  if (!esp_matter::is_started()) {
    return;
  }
  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  auto &bindingTable = chip::app::Clusters::Binding::Table::GetInstance();
  for (const auto &entry : bindingTable) {
    if (entry.local == local_endpoint_id &&
        entry.type == chip::app::Clusters::Binding::MATTER_UNICAST_BINDING) {
      action(entry);
    }
  }
}

} // namespace

// =======================================================================
// MARK: - OnOff Read/Subscribe Callback
// =======================================================================

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
      printf("[LIGHT] Bound device EP%u OnOff state: %s\n",
             path.mEndpointId, val ? "ON" : "OFF");
      update_local_led_shim(val);
    }
  }

  void OnError(CHIP_ERROR error) override {
    printf("[LIGHT] OnOff read/subscribe error: %" CHIP_ERROR_FORMAT "\n",
           error.Format());
  }

  void OnDone(chip::app::ReadClient *client) override {
    printf("[LIGHT] OnOff read/subscribe ended (client=%p)\n", (void *)client);
  }

  void OnSubscriptionEstablished(chip::SubscriptionId id) override {
    printf("[LIGHT] OnOff subscription established (id=%u)\n", (unsigned)id);
  }
};

static OnOffReadCallback sOnOffReadCallback;

// =======================================================================
// MARK: - Server / Group Callbacks (registered via init_client_callbacks_shim)
// =======================================================================

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

    // Forward the on/off command (Toggle, On, Off) to the bound remote device.
    // send_command() in Swift sets req.type = INVOKE_CMD, so this is the path
    // triggered by button press and IR remote.
    esp_matter::client::interaction::invoke::send_request(
        nullptr, peer_device, req_handle->command_path, "{}",
        send_command_success_callback, send_command_failure_callback,
        chip::NullOptional, chip::NullOptional);

    return;
  }

  // READ_ATTR: sync the current on/off state from a bound device (e.g. after
  // reconnection). OnOffReadCallback::OnAttributeData() calls
  // update_local_led_shim() to keep the local LED in sync.
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

  printf("[LIGHT] Unhandled request type: %d\n", req_handle->type);
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

// =======================================================================
// MARK: - extern "C" Binding / Subscription Shims
// =======================================================================

extern "C" {

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

void subscribe_to_bound_device_shim(uint16_t remote_endpoint_id,
                                    uint64_t node_id,
                                    uint8_t fabric_index) {
  if (!esp_matter::is_started()) {
    printf("[TBR] Skipping subscription before Matter start\n");
    return;
  }

  esp_matter::lock::ScopedChipStackLock lock(portMAX_DELAY);
  esp_matter::client::request_handle_t req;
  req.type = esp_matter::client::SUBSCRIBE_ATTR;
  req.attribute_path = get_onoff_attribute_path(remote_endpoint_id);

  esp_err_t err = esp_matter::client::connect(
      chip::Server::GetInstance().GetCASESessionManager(), fabric_index,
      node_id, &req);
  if (err != ESP_OK) {
    printf("[TBR] subscribe connect() failed for 0x%" PRIx64 ": %s\n",
           node_id, esp_err_to_name(err));
  }
  printf("[TBR] Subscribing to 0x%" PRIx64 " (Endpoint %d)\n", node_id,
         remote_endpoint_id);
}

void subscribe_to_all_bound_devices_shim(uint16_t local_endpoint_id) {
  do_for_unicast_bindings(local_endpoint_id, [](const auto &entry) {
    esp_matter::client::request_handle_t req;
    req.type = esp_matter::client::SUBSCRIBE_ATTR;
    req.attribute_path = get_onoff_attribute_path(entry.remote);

    esp_err_t err = esp_matter::client::connect(
        chip::Server::GetInstance().GetCASESessionManager(), entry.fabricIndex,
        entry.nodeId, &req);
    if (err != ESP_OK) {
      printf("[TBR] subscribe connect() failed for 0x%" PRIx64 ": %s\n",
             entry.nodeId, esp_err_to_name(err));
    }
    printf("[TBR] Auto-subscribing to 0x%" PRIx64 " (EP %d)\n", entry.nodeId,
           entry.remote);
  });
}

void read_bound_device_onoff_shim(uint16_t local_endpoint_id) {
  do_for_unicast_bindings(local_endpoint_id, [](const auto &entry) {
    esp_matter::client::request_handle_t req;
    req.type = esp_matter::client::READ_ATTR;
    req.attribute_path = get_onoff_attribute_path(entry.remote);

    esp_err_t err = esp_matter::client::connect(
        chip::Server::GetInstance().GetCASESessionManager(), entry.fabricIndex,
        entry.nodeId, &req);
    if (err != ESP_OK) {
      printf("[TBR] read connect() failed for 0x%" PRIx64 ": %s\n",
             entry.nodeId, esp_err_to_name(err));
    }
  });
}

} // extern "C"
