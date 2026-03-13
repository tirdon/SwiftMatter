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

esp_err_t esp_matter::attribute::set_callback_shim(callback_t_shim callback) {
  return set_callback((callback_t)callback);
}

esp_matter::cluster_t *esp_matter::cluster::get_shim(esp_matter::endpoint_t *endpoint, unsigned int cluster_id) {
  return get(endpoint, (uint32_t)cluster_id);
}

esp_matter::attribute_t *esp_matter::attribute::get_shim(esp_matter::cluster_t *cluster, unsigned int attribute_id) {
  return get(cluster, (uint32_t)attribute_id);
}

esp_err_t esp_matter::attribute::get_val_shim(unsigned short endpoint_id, unsigned int cluster_id, unsigned int attribute_id, esp_matter_attr_val_t *val) {
  return get_val(endpoint_id, (uint32_t)cluster_id, (uint32_t)attribute_id, (esp_matter_attr_val_t *) val);
}

void recomissionFabric() {
  if (chip::Server::GetInstance().GetFabricTable().FabricCount() == 0) {
    chip::CommissioningWindowManager & commissionMgr = chip::Server::GetInstance().GetCommissioningWindowManager();
    constexpr auto kTimeoutSeconds = chip::System::Clock::Seconds16(300);
    if (!commissionMgr.IsCommissioningWindowOpen()) {
      commissionMgr.OpenBasicCommissioningWindow(kTimeoutSeconds, chip::CommissioningWindowAdvertisement::kDnssdOnly);
    }
  }
}

esp_err_t esp_matter::attribute::update_shim(uint16_t endpoint_id, unsigned int cluster_id, unsigned int attribute_id,
                   esp_matter_attr_val_t *val) {
  return update(endpoint_id, (uint32_t)cluster_id, (uint32_t)attribute_id, val);
}

esp_err_t esp_matter::attribute::report_shim(unsigned short endpoint_id, unsigned int cluster_id, unsigned int attribute_id, esp_matter_attr_val_t* val) {
  return report((uint16_t) endpoint_id, (uint32_t) cluster_id, (uint32_t)attribute_id, (esp_matter_attr_val_t *)val);
}