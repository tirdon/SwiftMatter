// MARK: - Switch Endpoint

extension Matter {
    final class SwitchEndpoint: Endpoint {
        init(rootNode: Node) {
            var config = esp_matter.endpoint.on_off_plug_in_unit.config_t()
            config.on_off.on_off = false

            let endpoint = esp_matter.endpoint.on_off_plug_in_unit.create(
                rootNode.innerNode.node,
                &config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            // Binding cluster lets controllers bind this endpoint to remote devices
            var bindingConfig = esp_matter.cluster.binding.config_t()
            esp_matter.cluster.binding.create(
                endpoint,
                &bindingConfig,
                UInt8(esp_matter.CLUSTER_FLAG_SERVER.rawValue)
            )
            print("[TBR] Binding cluster added")

            // Add On/Off Client cluster to control remote devices via binding
            esp_matter.cluster.on_off.create(
                endpoint,
                nil,
                UInt8(esp_matter.CLUSTER_FLAG_CLIENT.rawValue)
            )
            print("[TBR] On/Off Client cluster added")

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}
