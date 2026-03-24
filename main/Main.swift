/// Maximum consecutive crashes before wiping NVS to clear corrupted session data.
private let crashThreshold: UInt8 = 3
/// Minutes of uptime before the crash counter resets (must exceed typical crash time).
private let stableMinutes: UInt32 = 10

/// Check NVS for consecutive crash count. If threshold is reached, erase NVS
/// (clears corrupted CHIP session/fabric data) and reboot with fresh state.
private func crashLoopGuard() {
	// NVS must be initialised before Matter.Node; nvs_flash_init is idempotent.
	let err = nvs_flash_init()
	if err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND {
		nvs_flash_erase()
		nvs_flash_init()
	}

	var handle: nvs_handle_t = 0
	guard nvs_open("crash_mon", NVS_READWRITE, &handle) == ESP_OK else { return }

	var count: UInt8 = 0
	nvs_get_u8(handle, "count", &count)

	if count >= crashThreshold {
		print("Crash loop detected (\(count) consecutive). Erasing NVS and rebooting...")
		nvs_close(handle)
		nvs_flash_erase()
		nvs_flash_init()
		esp_restart_shim()
	}

	nvs_set_u8(handle, "count", count &+ 1)
	nvs_commit(handle)
	nvs_close(handle)

	if count > 0 {
		print("Boot after crash (count: \(count + 1)/\(crashThreshold))")
	}
}

/// Reset crash counter to 0 (called after stable uptime).
private func resetCrashCounter() {
	var handle: nvs_handle_t = 0
	guard nvs_open("crash_mon", NVS_READWRITE, &handle) == ESP_OK else { return }
	nvs_set_u8(handle, "count", 0)
	nvs_commit(handle)
	nvs_close(handle)
	print("Crash counter reset — system stable")
}

@_cdecl("app_main")
func main() -> Never {

	print("Hello! Embedded Swift is running!")

	crashLoopGuard()

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

	// let humidityEndpoint = Matter.DHT22_humidityEndpoint(rootNode: rootNode)
	// let temperatureEndpoint = Matter.DHT22_tempEndpoint(rootNode: rootNode)

	let button = Button(endpoint: switchEndpoint.id, led: led)
	// let dht = DHT22Sensor(
	// 	humidityEndpoint: humidityEndpoint.id, temperatureEndpoint: temperatureEndpoint.id)

	rootNode.addEndpoint(switchEndpoint)
	// rootNode.addEndpoint(humidityEndpoint)
	// rootNode.addEndpoint(temperatureEndpoint)

	// xTaskCreate(
	// 	DHT22Sensor.dht_rx_task, "dht_rx_task", 4096, Unmanaged.passRetained(dht).toOpaque(), 3,
	// 	nil)

	// let ir = IRSensor(led: led)
	// xTaskCreate(
	// 	IRSensor.ir_rx_task, "ir_rx_task", 4096, Unmanaged.passRetained(ir).toOpaque(), 4,
	// 	nil)

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

	// Reset crash counter after stable uptime
	xTaskCreate(
		{ _ in
			vTaskDelay(msToTicks(stableMinutes * 60 * 1000))
			resetCrashCounter()
			vTaskDelete(nil)
		}, "crash_rst", 2048, nil, 1, nil)

	// Periodic heap monitoring
	xTaskCreate(
		{ _ in
			while true {
				vTaskDelay(msToTicks(30_000))
				let free = get_free_heap_size_shim()
				let minFree = get_min_free_heap_size_shim()
				print("Heap: free=\(free) min_ever=\(minFree)")
			}
		}, "heap_mon", 2048, nil, 1, nil)

	while true { sleep(1) }
}
