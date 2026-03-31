// Matter+Application.swift
// Matter application lifecycle — starts the Matter stack and handles device events.

extension Matter {
    final class Application {
        var rootNode: Matter.Node? = nil
        let led = Matter.OnBoardLED()

        init() {
            _ = Unmanaged.passRetained(self)
        }

        func start() {
            func callback(
                event: UnsafePointer<chip.DeviceLayer.ChipDeviceEvent>?,
                context: Int
            ) {
                guard let ptr = UnsafeRawPointer(bitPattern: context) else { return }
                let led = Unmanaged<Matter.OnBoardLED>.fromOpaque(ptr).takeUnretainedValue()
                guard let event else { return }

                let eventType = event.pointee.Type
                switch Int(eventType) {
                case chip.DeviceLayer.DeviceEventType.kFabricRemoved:
                    recomissionFabric()
                    print("Fabric removed")

                case Int(chip.DeviceLayer.DeviceEventType.kWiFiConnectivityChange.rawValue):
                    let result = event.pointee.WiFiConnectivityChange.Result
                    if result == chip.DeviceLayer.kConnectivity_Established {
                        led.enabled = false
                        print("WiFi connected")
                        printFabricInfo()
                    } else if result == chip.DeviceLayer.kConnectivity_Lost {
                        led.enabled = true
                        print("WiFi disconnected")
                    }

                default:
                    break
                }
            }

            let ledOpaque = Int(bitPattern: Unmanaged.passRetained(led).toOpaque())
            if esp_matter.start(callback, ledOpaque) == ESP_OK {
                print("Matter started successfully")
            } else {
                fatalError("Failed to start Matter")
            }
        }
    }
}
