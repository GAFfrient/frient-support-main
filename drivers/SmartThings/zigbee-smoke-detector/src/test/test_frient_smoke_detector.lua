-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local IASWD = clusters.IASWD
local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local capabilities = require "st.capabilities"
local alarm = capabilities.alarm
local smokeDetector = capabilities.smokeDetector
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"
local SirenConfiguration = require "st.zigbee.generated.zcl_clusters.IASWD.types.SirenConfiguration"
local ALARM_DEFAULT_MAX_DURATION = 0x00F0
local POWER_CONFIGURATION_ENDPOINT = 0x23
local IASZONE_ENDPOINT = 0x23
local TEMPERATURE_MEASUREMENT_ENDPOINT = 0x26
local base64 = require "base64"


local mock_device = test.mock_device.build_test_zigbee_device(
        { profile = t_utils.get_profile_definition("smoke-temp-battery-alarm.yml"),
          zigbee_endpoints = {
              [0x01] = {
                  id = 0x01,
                  manufacturer = "frient A/S",
                  model = "SMSZB-120",
                  server_clusters = { 0x0003, 0x0005, 0x0006 }
              },
              [0x23] = {
                  id = 0x23,
                  server_clusters = { 0x0000, 0x0001, 0x0003, 0x000f, 0x0020, 0x0500, 0x0502 }
              },
              [0x26] = {
                  id = 0x26,
                  server_clusters = { 0x0000, 0x0003, 0x0402 }
              }
          }
        }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
    test.mock_device.add_test_device(mock_device)
    zigbee_test_utils.init_noop_health_check_timer()
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
        "Clear alarm and smokeDetector states when the device is added", function()
            test.socket.matter:__set_channel_ordering("relaxed")
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", alarm.alarm.off())
            )

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", smokeDetector.smoke.clear())
            )

            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "init and doConfigure lifecycles should be handled properly",
        function()
            test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
            test.socket.zigbee:__set_channel_ordering("relaxed")

            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })

            test.wait_for_events()

            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", alarm.alarm.off())
            )

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", smokeDetector.smoke.clear())
            )

            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        PowerConfiguration.ID,
                        POWER_CONFIGURATION_ENDPOINT
                ):to_endpoint(POWER_CONFIGURATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
                        mock_device,
                        30,
                        21600,
                        1
                ):to_endpoint(POWER_CONFIGURATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        TemperatureMeasurement.ID,
                        TEMPERATURE_MEASUREMENT_ENDPOINT
                ):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        60,
                        600,
                        100
                ):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        IASZone.ID,
                        IASZONE_ENDPOINT
                ):to_endpoint(IASZONE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.ZoneStatus:configure_reporting(
                        mock_device,
                        30,
                        300,
                        0
                ):to_endpoint(IASZONE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.IASCIEAddress:write(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui
                ):to_endpoint(IASZONE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.server.commands.ZoneEnrollResponse(
                        mock_device,
                        IasEnrollResponseCode.SUCCESS,
                        0x00
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASWD.attributes.MaxDuration:write(mock_device, ALARM_DEFAULT_MAX_DURATION)
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
        end
)

test.register_message_test(
        "Battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 24) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(14))
            }
        }
)

test.register_message_test(
        "ZoneStatusChangeNotification should be handled: detected",
        {
            {
                channel = "zigbee",
                direction = "receive",
                -- ZoneStatus | Bit0 Alarm1 set to 1
                message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0001, 0x00) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
            }
        }
)

test.register_message_test(
        "ZoneStatusChangeNotification should be handled: tested",
        {
            {
                channel = "zigbee",
                direction = "receive",
                -- ZoneStatus | Bit8: Test set to 1
                message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x100, 0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
            }
        }
)

test.register_message_test(
        "Temperature report should be handled (C) for the temperature cluster",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
            }
        }
)

test.register_coroutine_test(
        "Health check should check all relevant attributes",
        function()
            test.wait_for_events()

            test.mock_time.advance_time(50000) -- battery is 21600 for max reporting interval
            test.socket.zigbee:__set_channel_ordering("relaxed")

            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
                    }
            )

            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
                    }
            )

            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        IASZone.attributes.ZoneStatus:read(mock_device)
                    }
            )
        end,
        {
            test_init = function()
                test.mock_device.add_test_device(mock_device)
                test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
            end
        }
)

test.register_message_test(
        "Refresh should read all necessary attributes",
        {
            {
                channel = "capability",
                direction = "receive",
                message = {
                    mock_device.id,
                    { capability = "refresh", component = "main", command = "refresh", args = {} }
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id,
                    IASZone.attributes.ZoneStatus:read(mock_device)
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id,
                    PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id,
                    TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
                }
            }
        },
        {
            inner_block_ordering = "relaxed"
        }
)

test.register_message_test(
        "Refresh should read all necessary attributes",
        {
            {
                channel = "capability",
                direction = "receive",
                message = {
                    mock_device.id,
                    { capability = "refresh", component = "main", command = "refresh", args = {} }
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id,
                    IASZone.attributes.ZoneStatus:read(mock_device)
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id,
                    PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id,
                    TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
                }
            }
        },
        {
            inner_block_ordering = "relaxed"
        }
)

test.register_coroutine_test(
        "infochanged to check for necessary preferences settings: tempSensitivity, warningDuration",
        function()
            local updates = {
                preferences = {
                    tempSensitivity = 1.3,
                    warningDuration = 100
                }
            }

            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

            test.socket.zigbee:__expect_send({
                mock_device.id,
                TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        60,
                        600,
                        130
                )--:to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASWD.attributes.MaxDuration:write(mock_device, 0x0064)--:to_endpoint(IASZONE_ENDPOINT)
            })


            test.socket.zigbee:__set_channel_ordering("relaxed")

        end
)

local sirenConfiguration = SirenConfiguration(0x00)
sirenConfiguration:set_warning_mode(0x01)
local defaultWarningDuration = 240

test.register_message_test(
        "Capability command Alarm - siren should be handled",
        {
            {
                channel = "capability",
                direction = "receive",
                message = {
                    mock_device.id,
                    { capability = "alarm", component = "main", command = "siren", args = {} }
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_device.id,
                            IASWD.server.commands.StartWarning(mock_device,
                                    sirenConfiguration,
                                    data_types.Uint16(defaultWarningDuration),
                                    data_types.Uint8(00),
                                    data_types.Enum8(00))
                }
            }
        },
        {
            inner_block_ordering = "relaxed"
        }
)

local sirenConfiguration = SirenConfiguration(0x00)
sirenConfiguration:set_warning_mode(0x00)

test.register_message_test(
        "Capability command Alarm - OFF should be handled",
        {
            {
                channel = "capability",
                direction = "receive",
                message = {
                    mock_device.id,
                    { capability = "alarm", component = "main", command = "off", args = {} }
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_device.id,
                            IASWD.server.commands.StartWarning(mock_device,
                                    sirenConfiguration,
                                    data_types.Uint16(0x00),
                                    data_types.Uint8(00),
                                    data_types.Enum8(00))
                }
            }
        },
        {
            inner_block_ordering = "relaxed"
        }
)


test.run_registered_tests()
