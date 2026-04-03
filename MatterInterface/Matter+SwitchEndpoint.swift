// MARK: - Switch Endpoint

extension Matter {
    final class LightEndpoint: Endpoint {
        init(rootNode: Node) {
            var config = esp_matter.endpoint.on_off_light.config_t()
            config.binding = .init()

            let endpoint = esp_matter.endpoint.on_off_light.create(
                rootNode.innerNode.node,
                &config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}
