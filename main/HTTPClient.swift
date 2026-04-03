/// Minimal HTTP client for posting sensor data as JSON.
final class SensorHTTPClient {
    private let url: UnsafePointer<CChar>

    init(url: UnsafePointer<CChar>) {
        self.url = url
    }

    /// Post sensor data as JSON. Returns true on success.
    func post(_ data: SensorData) -> Bool {
        let bufferSize = 128
        let jsonBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { jsonBuffer.deallocate() }

        let written = data.writeJSON(to: jsonBuffer, capacity: bufferSize)
        if written < 0 || written >= bufferSize {
            print("JSON serialization failed")
            return false
        }

        var statusCode: Int32 = 0
        let err = http_post_shim(url, jsonBuffer, Int32(written), &statusCode)

        if err == ESP_OK && statusCode >= 200 && statusCode < 300 {
            print("POST success (status \(statusCode))")
            return true
        } else {
            print("POST failed (err=\(err), status=\(statusCode))")
            return false
        }
    }
}
