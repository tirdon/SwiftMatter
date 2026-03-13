extension Matter {
    final class Application {
        var rootNode: Matter.Node? = nil
        let led: Matter.OnBoardLED = Matter.OnBoardLED()

        init() {
            // For now, leak the object, to be able to use local variables to declare
            // it. We don't expect this object to be created and destroyed repeatedly.
            _ = Unmanaged.passRetained(self)
        }

        func start() {
            func callback( event: UnsafePointer<chip.DeviceLayer.ChipDeviceEvent>?, context: Int ) {
                guard let ptr = UnsafeRawPointer(bitPattern: context) else { return }
                let led = Unmanaged<Matter.OnBoardLED>.fromOpaque(ptr).takeUnretainedValue()
                // Ignore callback if event not set.
                guard let event else { return }
                let eventType = event.pointee.Type
                switch Int(eventType) {
                    case chip.DeviceLayer.DeviceEventType.kFabricRemoved:
                        recomissionFabric()
                        print("Fabric removed")
                    case Int(chip.DeviceLayer.DeviceEventType.kWiFiConnectivityChange.rawValue):
                        print("WiFi connectivity change")
                        if event.pointee.WiFiConnectivityChange.Result == chip.DeviceLayer.kConnectivity_Established {
                        // gpio_set_level(GPIO_NUM_8, 1)
                            led.enabled = false
                            print("WiFi connected")
                        // esp_sntp_setoperatingmode(ESP_SNTP_OPMODE_POLL)
                        // esp_sntp_setservername(0, "th.pool.ntp.org")
                        // esp_sntp_init()
                        } else if event.pointee.WiFiConnectivityChange.Result == chip.DeviceLayer.kConnectivity_Lost {
                            // gpio_set_level(GPIO_NUM_8, 0)
                            led.enabled = true
                            print("WiFi disconnected")
                        }
                    default: break
                }
            }
            
            if esp_matter.start(callback, Int(bitPattern: Unmanaged.passRetained(led).toOpaque())) == ESP_OK {
                print("Matter started successfully")
            } else {
                fatalError("Failed to start Matter")
            }
        }
    }
}

