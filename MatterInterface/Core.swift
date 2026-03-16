// Core.swift
// Matter protocol hierarchy — defines the core abstractions for Nodes, Endpoints,
// Clusters, and Attributes that map to the esp_matter C API.

// MARK: - Node

protocol MatterNode {
    var node: UnsafeMutablePointer<esp_matter.node_t> { get }
}

// MARK: - Endpoint

protocol MatterEndpoint {
    var endpoint: UnsafeMutablePointer<esp_matter.endpoint_t> { get }
}

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

// MARK: - Cluster

protocol MatterCluster {
    var cluster: UnsafeMutablePointer<esp_matter.cluster_t> { get }
    init(cluster: UnsafeMutablePointer<esp_matter.cluster_t>)
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
        Attribute(attribute: esp_matter.attribute.get_shim(cluster, id.rawValue))
    }
}

// MARK: - Attribute

protocol MatterAttribute {
    var attribute: UnsafeMutablePointer<esp_matter.attribute_t> { get }
    init(attribute: UnsafeMutablePointer<esp_matter.attribute_t>)
}

extension MatterAttribute {
    var value: esp_matter_attr_val_t {
        var val = esp_matter_attr_val_t()
        esp_matter.attribute.get_val(attribute, &val)
        return val
    }
}

// MARK: - Attribute Event Type

enum MatterAttributeEventType: esp_matter.attribute.callback_type_t.RawValue {
    case willSet = 0
    case didSet  = 1
    case read    = 2
    case write   = 3

    var description: StaticString {
        switch self {
        case .willSet: "willSet: Pre-Update"
        case .didSet:  "didSet: Post-Update"
        case .read:    "read"
        case .write:   "write"
        }
    }
}

// MARK: - GPIO Protocol

protocol GPIO {
    var enabled: Bool { get set }
}
