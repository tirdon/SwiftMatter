// Core.swift


protocol MatterNode { var node: UnsafeMutablePointer<esp_matter.node_t> { get } }

// ====================================================

protocol MatterEndpoint { var endpoint: UnsafeMutablePointer<esp_matter.endpoint_t> { get } }

extension MatterEndpoint {
    var eid: UInt16 { esp_matter.endpoint.get_id(endpoint) }

    func cluster<Cluster: MatterCluster>(_ id: ClusterID<Cluster>) -> Cluster {
        Cluster(cluster: esp_matter.cluster.get_shim(endpoint, id.rawValue))
    }
}

protocol MatterConcreteEndpoint: MatterEndpoint {
    static var deviceTypeId: UInt32 { get }
    init(_ endpoint: UnsafeMutablePointer<esp_matter.endpoint_t>)
}

// extension MatterConcreteEndpoint {
//     init(_ endpoint: UnsafeMutablePointer<esp_matter.endpoint_t> ) {
//         self.endpoint = endpoint
//     }
// }

// ====================================================

protocol MatterCluster {
    var cluster: UnsafeMutablePointer<esp_matter.cluster_t> { get }
    init(cluster: UnsafeMutablePointer<esp_matter.cluster_t> )
}

extension MatterCluster {
    init?(endpoint: some MatterEndpoint, cluster id: UInt32) {
        guard let cluster = esp_matter.cluster.get_shim(endpoint.endpoint, id)
        else { return nil }
        self.init(cluster: cluster)
    }
}

protocol MatterConcreteCluster: MatterCluster {
    static var clusterId: ClusterID<Self> { get }
}

extension MatterConcreteCluster {
    func attribute<Attribute: MatterAttribute>(_ id: AttributeID<Attribute>) -> Attribute {
        Attribute(attribute: esp_matter.attribute.get_shim(cluster , id.rawValue))
    }
}

// ====================================================

protocol MatterAttribute {
    var attribute: UnsafeMutablePointer<esp_matter.attribute_t> { get }
    init(attribute: UnsafeMutablePointer<esp_matter.attribute_t> )
}

extension MatterAttribute {
    var value: esp_matter_attr_val_t {
        var val = esp_matter_attr_val_t()
        esp_matter.attribute.get_val(attribute, &val)
        return val
    }
}

// protocol MatterConcreteAttribute: MatterAttribute {
//     static var attributeId: AttributeID<Self> { get }
// }

// ====================================================

enum MatterAttributeEventType: esp_matter.attribute.callback_type_t.RawValue {
    case willSet = 0
    case didSet = 1
    case read = 2
    case write = 3

    var description: StaticString {
        switch self {
            case .willSet: "willSet: Pre-Update"
            case .didSet: "didSet: Post-Update"
            case .read: "read"
            case .write: "write"
        }
    }
}

// protocol MatterCommand {
//     static var commandId: UInt32 { get }
// }

// protocol MatterEvent {
//     static var eventId: UInt32 { get }
// }

// ====================================================

protocol GPIO {
    var enabled: Bool { get set }
}


// MARK: - Root Node
// ====================================================

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
        guard let context else {
            return ESP_OK
        }
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
    guard let node = esp_matter.node.create_raw() else {
        return nil
    }

    name.withCString { name in
        let length = strnlen(name, Int(esp_matter.cluster.basic_information.k_max_node_label_length))
        withUnsafeMutablePointer(to: &nodeConfig.root_node.basic_information) { ptr in  
            _ = strncpy(ptr, name, length)
        }
    }

    let context = Context(attribute: attribute, identify: identify)
    withUnsafeMutablePointer(to: &nodeConfig.root_node) {
        // Transfer ownership to the node. This is a leak for now, but we don't expect nodes to be created and destroyed repeatedly.
        _ = esp_matter.endpoint.root_node.create(
            node, $0, UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue), Unmanaged.passRetained(context).toOpaque())
    }
    self.node = node
    self.context = context
    }

    var endpoint: Endpoint {
        Endpoint(esp_matter.endpoint.get(node, 0))
    }
}

//MARK: - Endpoints, Clusters, Attributes
// ====================================================

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

// ====================================================

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

// ====================================================

struct Attribute: MatterAttribute {
    var attribute: UnsafeMutablePointer<esp_matter.attribute_t>

    init(attribute: UnsafeMutablePointer<esp_matter.attribute_t>) {
        self.attribute = attribute
    }
}


// ====================================================


func print(_ a: Matter.Endpoint.Attribute) {
    switch a {
        case .onOff: print("onOff")
        case .dht22update: print("DHT22 updated attributes")
        case .unknown(let id): print("unknown attribute id: \(id)")
    }
}