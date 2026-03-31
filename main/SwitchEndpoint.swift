// SwitchEndpoint.swift

extension Matter {
    class SwitchEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.power_source.get_device_type_id()
        }

        init(rootNode: Node) {
            // Use the built-in Power Source device type as the switch template here.
            var config = esp_matter.endpoint.power_source.config_t()

            // Create the endpoint on the root node with the shared Matter context.
            let endpoint = esp_matter.endpoint.power_source.create(
                rootNode.innerNode.node,
                &config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            // Store the endpoint id so higher-level Swift code can route events to it.
            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

// Template endpoint for a simple Matter-controlled switch or relay.
