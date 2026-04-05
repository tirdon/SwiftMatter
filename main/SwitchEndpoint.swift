// SwitchEndpoint.swift

func send_command(to endpoint: UInt16, with commandID: chip.CommandId) {
    if !esp_matter.is_started() { return }
    var req = esp_matter.client.request_handle_t()
    req.type = esp_matter.client.INVOKE_CMD

    req.command_path.mClusterId = chip.app.Clusters.OnOff.Id
    req.command_path.mCommandId = commandID
    esp_matter.client.cluster_update_shim(endpoint, &req)
}

//MARK: SwitchClientEndpoint
extension Matter {
    class SwitchClientEndpoint: Endpoint {
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

//MARK: SwitchEndpoint (end device)
extension Matter {
    class SwitchEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.on_off_plug_in_unit.get_device_type_id()
        }

        init(rootNode: Node) {
            var config = esp_matter.endpoint.on_off_plug_in_unit.config_t()
            config.on_off.on_off = false

            let endpoint = esp_matter.endpoint.on_off_plug_in_unit.create(
                rootNode.innerNode.node,
                &config,
                UInt8(esp_matter.ENDPOINT_FLAG_NONE.rawValue),
                Unmanaged.passRetained(rootNode.innerNode.context).toOpaque()
            )

            super.init(rootNode: rootNode, endpoint: esp_matter.endpoint.get_id(endpoint))
        }
    }
}

extension Matter {
    final class DHT22_tempEndpoint: Endpoint {
        static var deviceTypeId: UInt32 {
            esp_matter.endpoint.temperature_sensor.get_device_type_id()
        }

        init(rootNode: Node) {
            var t_config = esp_matter.endpoint.temperature_sensor.config_t()
            t_config.temperature_measurement.max_measured_value = .init(111_00)
            t_config.temperature_measurement.min_measured_value = .init(-33_00)
            t_config.temperature_measurement.measured_value = .init(111_00)

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
