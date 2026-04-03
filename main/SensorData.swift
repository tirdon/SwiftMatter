/// Raw sensor data received over SPI: 3 little-endian Float32 values = 12 bytes.
struct SensorData {
    var temperature: Float
    var humidity: Float
    var soilMoisture: Float

    /// Total byte size of the SPI payload.
    static let wireSize: Int = 12  // 3 * MemoryLayout<Float>.size

    /// Parse from a 12-byte SPI receive buffer (little-endian floats).
    init?(from buffer: UnsafePointer<UInt8>, length: Int) {
        guard length >= SensorData.wireSize else { return nil }
        let raw = UnsafeRawPointer(buffer)
        self.temperature  = raw.load(as: Float.self)
        self.humidity     = raw.load(fromByteOffset: 4, as: Float.self)
        self.soilMoisture = raw.load(fromByteOffset: 8, as: Float.self)
    }

    /// Build JSON string into a pre-allocated buffer using C snprintf.
    /// Returns the number of bytes written (not including null terminator).
    func writeJSON(to buffer: UnsafeMutablePointer<CChar>, capacity: Int) -> Int {
        return Int(snprintf_sensor_json_shim(
            buffer, Int32(capacity), temperature, humidity, soilMoisture))
    }
}
