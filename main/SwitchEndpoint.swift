// SwitchEndpoint.swift

extension Matter {
    class SwitchEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.on_off_light_switch.get_device_type_id()
        }

        init(rootNode: Node) {
            var config = esp_matter.endpoint.on_off_light_switch.config_t()
            config.binding = .init()

            let endpoint = esp_matter.endpoint.on_off_light_switch.create(
                rootNode.innerNode.node,
                &config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

/*
extension Matter {
    final class DHT22_tempEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.temperature_sensor.get_device_type_id()
        }

        init(rootNode: Node) {
            var t_config = esp_matter.endpoint.temperature_sensor.config_t()
            t_config.temperature_measurement.max_measured_value = .init(125_00)
            t_config.temperature_measurement.min_measured_value = .init(-40_00)
            t_config.temperature_measurement.measured_value = .init(101_00)

            let endpoint = esp_matter.endpoint.temperature_sensor.create(
                rootNode.innerNode.node,
                &t_config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

extension Matter {
    final class DHT22_humidityEndpoint: Endpoint {
        static var deviceTypeId: UInt32 { esp_matter.endpoint.humidity_sensor.get_device_type_id() }

        init(rootNode: Node) {
            var h_config = esp_matter.endpoint.humidity_sensor.config_t()
            h_config.relative_humidity_measurement.max_measured_value = .init(100_00)
            h_config.relative_humidity_measurement.min_measured_value = .init(0)
            h_config.relative_humidity_measurement.measured_value = .init(0)

            let endpoint = esp_matter.endpoint.humidity_sensor.create(
                rootNode.innerNode.node,
                &h_config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

extension Matter {
    final class SoilMoistureEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.dimmable_light.get_device_type_id()
        }

        init(rootNode: Node) {
            var l_config = esp_matter.endpoint.dimmable_light.config_t()
            l_config.level_control_lighting.max_level = .init(100)
            l_config.level_control_lighting.min_level = .init(0)
            l_config.level_control.on_level = .init(80)
            l_config.level_control.current_level = .init(80)

            let endpoint = esp_matter.endpoint.dimmable_light.create(
                rootNode.innerNode.node,
                &l_config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}
*/
