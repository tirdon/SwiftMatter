// Core+RootNode.swift
// Concrete types for the Matter data model: RootNode, Endpoint, Cluster, Attribute.

// MARK: - Root Node

struct RootNode: MatterNode {
    typealias AttributeCallback = (
        MatterAttributeEventType, Endpoint, Cluster, UInt32,
        UnsafeMutablePointer<esp_matter_attr_val_t>?
    ) -> Void
    typealias IdentifyCallback = (
        esp_matter.identification.callback_type_t, UInt16, UInt8, UInt8
    ) -> Void

    final class Context {
        var attribute: AttributeCallback
        var identify: IdentifyCallback

        init(
            attribute: @escaping AttributeCallback,
            identify: @escaping IdentifyCallback
        ) {
            self.attribute = attribute
            self.identify = identify
        }
    }

    var node: UnsafeMutablePointer<esp_matter.node_t>
    let context: Context

    init?(
        name: String,
        attribute: @escaping AttributeCallback,
        identify: @escaping IdentifyCallback
    ) {
        var nodeConfig = esp_matter.node.config_t()

        esp_matter.attribute.set_callback_shim {
            type, endpoint, cluster, attribute, value, context in
            guard let context else { return ESP_OK }
            guard let e = Endpoint(id: endpoint) else { return ESP_OK }
            guard let c = Cluster(endpoint: e, cluster: cluster) else { return ESP_OK }
            guard let event = MatterAttributeEventType(rawValue: type.rawValue) else {
                fatalError("Unknown event type")
            }
            let ctx = Unmanaged<Context>.fromOpaque(context).takeUnretainedValue()
            ctx.attribute(event, e, c, attribute, value)
            return ESP_OK
        }

        esp_matter.identification.set_callback {
            type, endpoint, effect, variant, context in
            guard let context else { fatalError("context must be non-nil") }
            Unmanaged<Context>.fromOpaque(context).takeUnretainedValue().identify(
                type, endpoint, effect, variant)
            return ESP_OK
        }

        guard let node = esp_matter.node.create_raw() else { return nil }

        name.withCString { name in
            let length = strnlen(
                name, Int(esp_matter.cluster.basic_information.k_max_node_label_length))
            withUnsafeMutablePointer(to: &nodeConfig.root_node.basic_information) { ptr in
                _ = strncpy(ptr, name, length)
            }
        }

        let context = Context(attribute: attribute, identify: identify)
        withUnsafeMutablePointer(to: &nodeConfig.root_node) {
            _ = esp_matter.endpoint.root_node.create(
                node, $0, UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(context).toOpaque())
        }
        self.node = node
        self.context = context
    }

    var endpoint: Endpoint {
        Endpoint(esp_matter.endpoint.get(node, 0))
    }
}

// MARK: - Endpoint

struct Endpoint: MatterEndpoint {
    var endpoint: UnsafeMutablePointer<esp_matter.endpoint_t>

    init(_ endpoint: UnsafeMutablePointer<esp_matter.endpoint_t>) {
        self.endpoint = endpoint
    }

    init?(id: UInt16) {
        guard let root = esp_matter.node.get() else { return nil }
        guard let endpoint = esp_matter.endpoint.get(root, id) else { return nil }
        self.init(endpoint)
    }

    func `as`<T: MatterConcreteEndpoint>(_ type: T.Type) -> T? {
        let expected = T.deviceTypeId
        let count = esp_matter.endpoint.get_device_type_count(endpoint)
        for i in 0..<count {
            var deviceTypeId: UInt32 = 0
            var deviceTypeVersion: UInt8 = 0
            let err = esp_matter.endpoint.get_device_type_at_index(
                endpoint, i, &deviceTypeId, &deviceTypeVersion)
            if err == ESP_OK && deviceTypeId == expected {
                return T(endpoint)
            }
        }
        return nil
    }
}

// MARK: - Cluster

struct Cluster: MatterCluster {
    var cluster: UnsafeMutablePointer<esp_matter.cluster_t>

    init(cluster: UnsafeMutablePointer<esp_matter.cluster_t>) {
        self.cluster = cluster
    }

    func `as`<T: MatterConcreteCluster>(_ type: T.Type) -> T? {
        let expected = T.clusterId
        let id = esp_matter.cluster.get_id(cluster)
        if id == expected.rawValue {
            return T(cluster: cluster)
        }
        return nil
    }
}

// MARK: - Attribute

struct Attribute: MatterAttribute {
    var attribute: UnsafeMutablePointer<esp_matter.attribute_t>

    init(attribute: UnsafeMutablePointer<esp_matter.attribute_t>) {
        self.attribute = attribute
    }
}
