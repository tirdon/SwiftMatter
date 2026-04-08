// SwitchEndpoint.swift
// Matter OnOff switch client endpoint and command helper.

/// Send an OnOff cluster command to all bound devices on the given endpoint.
func send_command(to endpoint: UInt16, with commandID: chip.CommandId) {
    if !esp_matter.is_started() { return }
    var req = esp_matter.client.request_handle_t()
    req.type = esp_matter.client.INVOKE_CMD

    req.command_path.mClusterId = chip.app.Clusters.OnOff.Id
    req.command_path.mCommandId = commandID
    esp_matter.client.cluster_update_shim(endpoint, &req)
}

//MARK: - Switch Client Endpoint

extension Matter {
    class SwitchClientEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.on_off_light_switch.get_device_type_id()
        }

        init(rootNode: Node) {
            var config = esp_matter.endpoint.on_off_light_switch.config_t()
            config.binding = .init()

            let endpoint = esp_matter.endpoint.on_off_light_switch.create(
                rootNode.innerNode.node,
                &config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}
