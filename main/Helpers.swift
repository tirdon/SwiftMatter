// Helpers.swift
// Shared utility functions for FreeRTOS timing and GPIO.

// MARK: - Timing

/// Convert milliseconds to FreeRTOS ticks.
func msToTicks(_ ms: UInt32) -> UInt32 {
    ms * UInt32(configTICK_RATE_HZ) / 1000
}

/// Busy-wait delay for the given number of microseconds.
func delayUs(_ us: Int64) {
    let start = esp_timer_get_time()
    while (esp_timer_get_time() - start) < us {}
}
