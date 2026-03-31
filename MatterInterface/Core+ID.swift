// Core+ID.swift
// Type-safe ID wrappers and concrete cluster/attribute types.

// MARK: - Cluster ID

struct ClusterID<Cluster: MatterCluster>: RawRepresentable {
    let rawValue: UInt32
    static var identify: ClusterID<Identify> { .init(rawValue: chip.app.Clusters.Identify.Id) }
    static var onOff: ClusterID<OnOffControl> { .init(rawValue: chip.app.Clusters.OnOff.Id) }
}

// MARK: - Attribute ID

struct AttributeID<Attribute: MatterAttribute>: RawRepresentable {
    let rawValue: UInt32
}

// MARK: - Identify Cluster

struct Identify: MatterConcreteCluster {
    static var clusterId: ClusterID<Self> { .identify }
    let cluster: UnsafeMutablePointer<esp_matter.cluster_t>
}

// MARK: - OnOff Cluster

struct OnOffControl: MatterConcreteCluster {
    static var clusterId: ClusterID<Self> { .onOff }
    let cluster: UnsafeMutablePointer<esp_matter.cluster_t>

    struct OnOffState: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    static var onOff: AttributeID<OnOffState> {
        .init(rawValue: chip.app.Clusters.OnOff.Attributes.OnOff.Id)
    }

    var onOffState: OnOffState { attribute(OnOffControl.onOff) }
}
