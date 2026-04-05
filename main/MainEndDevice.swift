// @_cdecl("app_main")
func main() -> Never {

	print("Hello! Embedded Swift is running!")

	let led = LED()

	let rootNode = Matter.Node(name: "Irrigation ")
	rootNode.identifyHandler = { print("identify") }

	let switchEndpoint = Matter.SwitchEndpoint(rootNode: rootNode)

	switchEndpoint.eventHandler = { event in
		guard event.type == .didSet else { return }
		switch event.attribute {
		case .onOff:
			led.enabled = (event.value != 0)
			print("Switch is now \(led.enabled ? "ON" : "OFF")")
		case .unknown(let id): print("unknown attribute id: \(id)")
		}
	}

	let humidityEndpoint = Matter.DHT22_humidityEndpoint(rootNode: rootNode)
	let temperatureEndpoint = Matter.DHT22_tempEndpoint(rootNode: rootNode)

	let button = Button(endpoint: switchEndpoint.id, led: led)
	let dht = DHT22Sensor(
		humidityEndpoint: humidityEndpoint.id, temperatureEndpoint: temperatureEndpoint.id)
	let ir = IRSensor(button: button)

	rootNode.addEndpoint(switchEndpoint)
	rootNode.addEndpoint(humidityEndpoint)
	rootNode.addEndpoint(temperatureEndpoint)

	let app = Matter.Application()
	app.rootNode = rootNode
	app.start()

	sleep(1)

	xTaskCreate(
		DHT22Sensor.dht_rx_task,
		"dht_rx_task",
		4096,
		Unmanaged.passRetained(dht).toOpaque(),
		5,
		nil)

	xTaskCreate(
		IRSensor.ir_rx_task,
		"ir_rx_task",
		4096,
		Unmanaged.passRetained(ir).toOpaque(),
		3,
		nil)

	xTaskCreate(
		Button.button_task,
		"button_task",
		4096,
		Unmanaged.passRetained(button).toOpaque(),
		4,
		nil)

	while true { sleep(1) }
}
