//MARK: - Entrypoint

var globalLED: LED!

@_cdecl("update_local_led_shim")
func updateLocalLED(state: Bool) {
    globalLED?.enabled = state
}

@_cdecl("app_main")
func main() -> Never {

    print("Hello! Embedded Swift is running!")

    globalLED = LED()

    let rootNode = Matter.Node(name: "Irrigation Controller")
    rootNode.identifyHandler = { print("identify") }

    let switchEndpoint = Matter.SwitchClientEndpoint(rootNode: rootNode)

    // let humidityEndpoint = Matter.DHT22_humidityEndpoint(rootNode: rootNode)
    // let temperatureEndpoint = Matter.DHT22_tempEndpoint(rootNode: rootNode)

    let button = Button(endpoint: switchEndpoint.id)
    // let dht = DHT22Sensor(
    // 	humidityEndpoint: humidityEndpoint.id, temperatureEndpoint: temperatureEndpoint.id)
    let ir = IRSensor(endpoint: switchEndpoint.id)

    rootNode.addEndpoint(switchEndpoint)
    // rootNode.addEndpoint(humidityEndpoint)
    // rootNode.addEndpoint(temperatureEndpoint)

    if esp_matter.client.init_client_callbacks_shim() != ESP_OK {
        fatalError("Failed to initialize Matter client callbacks")
    }

    let app = Matter.Application()
    app.rootNode = rootNode
    app.start()

    while !esp_matter.is_started() {
        vTaskDelay(msToTicks(100))
    }

    button.start()
    ir.start()

    // xTaskCreate(
    // 	DHT22Sensor.dht_rx_task,
    // 	"dht_rx_task",
    // 	4096,
    // Unmanaged.passRetained(dht).toOpaque(),
    // 5,
    // nil)

    while true { sleep(1) }
}
