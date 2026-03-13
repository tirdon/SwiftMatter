/// Typed wrapper for a cluster ID, parameterised on the concrete cluster type.
struct ClusterID<Cluster: MatterCluster>: RawRepresentable {
    let rawValue: UInt32

    static var identify: ClusterID<Identify> { .init(rawValue: chip.app.Clusters.Identify.Id) }
    static var onOff: ClusterID<OnOffControl> { .init(rawValue: chip.app.Clusters.OnOff.Id) }
    static var temperature_measurement: ClusterID<TemperatureMeasurementCluster> { .init(rawValue: chip.app.Clusters.TemperatureMeasurement.Id)}
    static var humidity_measurement: ClusterID<HumidityMeasurementCluster> { .init(rawValue: chip.app.Clusters.RelativeHumidityMeasurement.Id)}


}

// protocol MatterConcreteAttribute: RawRepresentable where RawValue == UInt32 {
//   associatedtype Attribute: MatterAttribute
// }

struct AttributeID<Attribute: MatterAttribute>: RawRepresentable {
    let rawValue: UInt32
}

// ====================================================

struct Identify: MatterConcreteCluster {
    static var clusterId: ClusterID<Self> { .identify }
    let cluster: UnsafeMutablePointer<esp_matter.cluster_t>
}
 
// ====================================================

struct OnOffControl: MatterConcreteCluster {
    static var clusterId: ClusterID<Self> { .onOff }
    let cluster: UnsafeMutablePointer<esp_matter.cluster_t>

    struct OnOffState: MatterAttribute { let attribute: UnsafeMutablePointer<esp_matter.attribute_t> }

    static var onOff: AttributeID<OnOffState> { .init(rawValue: chip.app.Clusters.OnOff.Attributes.OnOff.Id) }
  
    var onOffState: OnOffState { attribute(OnOffControl.onOff) }
}

// ====================================================

struct TemperatureMeasurementCluster: MatterConcreteCluster {
    static var clusterId: ClusterID<Self> { .temperature_measurement }
    let cluster: UnsafeMutablePointer<esp_matter.cluster_t>

    struct MeasuredValue: MatterAttribute { let attribute: UnsafeMutablePointer<esp_matter.attribute_t> }
    
    static var measuredValue: AttributeID<MeasuredValue> { .init(rawValue: chip.app.Clusters.TemperatureMeasurement.Attributes.MeasuredValue.Id) }

    var measuredValueState: MeasuredValue { attribute(TemperatureMeasurementCluster.measuredValue) }
}

struct HumidityMeasurementCluster: MatterConcreteCluster {
    static var clusterId: ClusterID<Self> { .humidity_measurement }
    let cluster: UnsafeMutablePointer<esp_matter.cluster_t>

    struct MeasuredValue: MatterAttribute { let attribute: UnsafeMutablePointer<esp_matter.attribute_t> }

    static var measuredValue: AttributeID<MeasuredValue> { .init(rawValue: chip.app.Clusters.RelativeHumidityMeasurement.Attributes.MeasuredValue.Id) }

    var measuredValueState: MeasuredValue { attribute(HumidityMeasurementCluster.measuredValue) }

}