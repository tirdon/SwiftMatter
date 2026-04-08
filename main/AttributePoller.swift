// AttributePoller.swift
// Periodically reads the OnOff attribute from all bound devices
// to keep the local LED state in sync even if a subscription drops.

final class AttributePoller {
	/// How often to poll (seconds).
	private let intervalSec: UInt32

	/// Local endpoint whose bindings we read from.
	private let endpointId: UInt16

	init(endpoint: UInt16, pollIntervalSec: UInt32 = 30) {
		self.endpointId = endpoint
		self.intervalSec = pollIntervalSec
	}

	static let pollTask: @convention(c) (UnsafeMutableRawPointer?) -> Void = { param in
		guard let param else { vTaskDelete(nil); return }
		let poller = Unmanaged<AttributePoller>.fromOpaque(param).takeUnretainedValue()

		// Wait for Matter + subscriptions to be established first
		vTaskDelay(msToTicks(10_000))
		print("[TBR/Poll] Attribute polling started (every \(poller.intervalSec)s)")

		while true {
			esp_matter.client.read_bound_device_onoff_shim(poller.endpointId)
			vTaskDelay(msToTicks(poller.intervalSec * 1000))
		}
	}

	func start() {
		xTaskCreate(
			AttributePoller.pollTask,
			"attr_poll",
			4096,
			Unmanaged.passUnretained(self).toOpaque(),
			2,
			nil
		)
	}
}
