// Core+ID.swift
// Type-safe ID wrappers and concrete cluster/attribute types.

// MARK: - Cluster ID

struct ClusterID<Cluster: MatterCluster>: RawRepresentable {
    let rawValue: UInt32

    static var accessControl: ClusterID<AccessControl> {
        .init(rawValue: chip.app.Clusters.AccessControl.Id)
    }
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

// MARK: - Access Control Cluster

struct AccessControl: MatterConcreteCluster {
    static var clusterId: ClusterID<Self> { .accessControl }
    let cluster: UnsafeMutablePointer<esp_matter.cluster_t>

    struct ACL: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    struct ExtensionAttribute: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    struct SubjectsPerAccessControlEntryAttribute: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    struct TargetsPerAccessControlEntryAttribute: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    struct AccessControlEntriesPerFabricAttribute: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    struct CommissioningARLAttribute: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    struct ARLAttribute: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    struct AuxiliaryACLAttribute: MatterAttribute {
        let attribute: UnsafeMutablePointer<esp_matter.attribute_t>
    }

    static var aclAttribute: AttributeID<ACL> {
        .init(rawValue: chip.app.Clusters.AccessControl.Attributes.Acl.Id)
    }

    static var extensionAttribute: AttributeID<ExtensionAttribute> {
        .init(rawValue: chip.app.Clusters.AccessControl.Attributes.Extension.Id)
    }

    static var subjectsPerAccessControlEntryAttribute: AttributeID<
        SubjectsPerAccessControlEntryAttribute
    > {
        .init(
            rawValue: chip.app.Clusters.AccessControl.Attributes.SubjectsPerAccessControlEntry.Id
        )
    }

    static var targetsPerAccessControlEntryAttribute: AttributeID<
        TargetsPerAccessControlEntryAttribute
    > {
        .init(
            rawValue: chip.app.Clusters.AccessControl.Attributes.TargetsPerAccessControlEntry.Id
        )
    }

    static var accessControlEntriesPerFabricAttribute: AttributeID<
        AccessControlEntriesPerFabricAttribute
    > {
        .init(
            rawValue: chip.app.Clusters.AccessControl.Attributes.AccessControlEntriesPerFabric.Id
        )
    }

    static var commissioningARLAttribute: AttributeID<CommissioningARLAttribute> {
        .init(rawValue: chip.app.Clusters.AccessControl.Attributes.CommissioningARL.Id)
    }

    static var arlAttribute: AttributeID<ARLAttribute> {
        .init(rawValue: chip.app.Clusters.AccessControl.Attributes.Arl.Id)
    }

    static var auxiliaryACLAttribute: AttributeID<AuxiliaryACLAttribute> {
        .init(rawValue: chip.app.Clusters.AccessControl.Attributes.AuxiliaryACL.Id)
    }

    var acl: ACL { attribute(Self.aclAttribute) }

    var extensionData: ExtensionAttribute? {
        attributeIfPresent(Self.extensionAttribute)
    }

    var subjectsPerAccessControlEntry: SubjectsPerAccessControlEntryAttribute {
        attribute(Self.subjectsPerAccessControlEntryAttribute)
    }

    var targetsPerAccessControlEntry: TargetsPerAccessControlEntryAttribute {
        attribute(Self.targetsPerAccessControlEntryAttribute)
    }

    var accessControlEntriesPerFabric: AccessControlEntriesPerFabricAttribute {
        attribute(Self.accessControlEntriesPerFabricAttribute)
    }

    var commissioningARL: CommissioningARLAttribute? {
        attributeIfPresent(Self.commissioningARLAttribute)
    }

    var arl: ARLAttribute? {
        attributeIfPresent(Self.arlAttribute)
    }

    var auxiliaryACL: AuxiliaryACLAttribute? {
        attributeIfPresent(Self.auxiliaryACLAttribute)
    }
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
