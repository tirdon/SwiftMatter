@_cdecl("app_main")
func main() -> Never {

	print("Hello! Embedded Swift is running!")

	let led = LED()

	let rootNode = Matter.Node(name: "Irrigation Controller")
	rootNode.identifyHandler = { print("identify") }

	let switchEndpoint = Matter.SwitchEndpoint(rootNode: rootNode)

	switchEndpoint.eventHandler = { event in
		guard event.type == .didSet else { return }
		switch event.attribute {
		case .onOff:
			led.enabled = (event.value == 1)
			print("Switch is now \(led.enabled ? "ON" : "OFF")")
		case .dht22update: break
		case .unknown(let id): print("unknown attribute id: \(id)")
		}
	}

	let humidityEndpoint = Matter.DHT22_humidityEndpoint(rootNode: rootNode)
	let temperatureEndpoint = Matter.DHT22_tempEndpoint(rootNode: rootNode)

	let button = Button(endpoint: switchEndpoint.id, led: led)
	let dht = DHT22Sensor(
		humidityEndpoint: humidityEndpoint.id, temperatureEndpoint: temperatureEndpoint.id)

	rootNode.addEndpoint(switchEndpoint)
	rootNode.addEndpoint(humidityEndpoint)
	rootNode.addEndpoint(temperatureEndpoint)

	xTaskCreate(
		DHT22Sensor.dht_rx_task, "dht_rx_task", 4096, Unmanaged.passRetained(dht).toOpaque(), 4,
		nil)

	let ir = IRSensor()
	xTaskCreate(
		IRSensor.ir_rx_task, "ir_rx_task", 4096, Unmanaged.passRetained(ir).toOpaque(), 4,
		nil)

	iot_button_new_gpio_device(&button.buttonConfig, &button.buttonGpioConfig, &button.buttonHandle)
	iot_button_register_cb(
		button.buttonHandle, BUTTON_PRESS_DOWN, nil,
		{ handle, data in
			guard let data else { return }

			let button = Unmanaged<Button>.fromOpaque(data).takeUnretainedValue()
			button.update()
			print("button is pressed.")

		}, Unmanaged.passUnretained(button).toOpaque())

	let app = Matter.Application()
	app.rootNode = rootNode
	app.start()

	while true { sleep(1) }
}
