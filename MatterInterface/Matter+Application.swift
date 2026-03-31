// Matter+Application.swift
// Matter application lifecycle — starts the Matter stack and handles device events.

extension Matter {
    final class Application {
        var rootNode: Matter.Node? = nil
        let led = Matter.OnBoardLED()

        init() { _ = Unmanaged.passRetained(self) }

        private func subscribeToBoundDevices() {
            // guard let rootNode else { return }
            // for endpoint in rootNode.endpoints {
            //     esp_matter.client.subscribe_to_bound_devices_shim(endpoint.id)
            // }
            return
        }

        func start() {
            func callback(
                event: UnsafePointer<chip.DeviceLayer.ChipDeviceEvent>?,
                context: Int
            ) {
                guard let ptr = UnsafeRawPointer(bitPattern: context) else { return }
                let app = Unmanaged<Matter.Application>.fromOpaque(ptr).takeUnretainedValue()
                guard let event else { return }

                let eventType = event.pointee.Type
                switch Int(eventType) {
                case chip.DeviceLayer.DeviceEventType.kFabricRemoved:
                    recomissionFabric()
                    print("Fabric removed")
                    printFabricInfo()

                case chip.DeviceLayer.DeviceEventType.kFabricCommitted:
                    print("Fabric committed")
                    printFabricInfo()
                    app.subscribeToBoundDevices()

                case chip.DeviceLayer.DeviceEventType.kFabricUpdated:
                    print("Fabric updated")
                    printFabricInfo()
                    app.subscribeToBoundDevices()

                case Int(chip.DeviceLayer.DeviceEventType.kWiFiConnectivityChange.rawValue):
                    let result = event.pointee.WiFiConnectivityChange.Result
                    if result == chip.DeviceLayer.kConnectivity_Established {
                        app.led.enabled = false
                        print("WiFi connected")
                        printStationIP()
                        printFabricInfo()
                        app.subscribeToBoundDevices()
                    } else if result == chip.DeviceLayer.kConnectivity_Lost {
                        app.led.enabled = true
                        print("WiFi disconnected")
                    }

                case Int(chip.DeviceLayer.DeviceEventType.kBindingsChangedViaCluster.rawValue):
                    print("Bindings changed")
                    app.subscribeToBoundDevices()

                default:
                    break
                }
            }

            let appOpaque = Int(bitPattern: Unmanaged.passRetained(self).toOpaque())
            if esp_matter.start(callback, appOpaque) == ESP_OK {
                print("Matter started successfully")
            } else {
                fatalError("Failed to start Matter")
            }
        }
    }
}
