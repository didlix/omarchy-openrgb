import QtQuick
import QtTest
import Quickshell.Io
import "../.."

// Unit tests for Service.qml under stubbed Quickshell modules (see
// tests/qml/imports). Covers the glue the Python CLI suite can't reach:
// optimistic updates, latest-wins command coalescing, hook-check exit-code
// mapping, and state-file parsing.
TestCase {
  name: "ServiceTests"

  property var service: null

  Component {
    id: serviceComponent
    Service {}
  }

  function init() {
    ProcessRegistry.reset()
    FileViewRegistry.reset()
    service = serviceComponent.createObject(this)
    verify(service !== null)
    // Component.onCompleted spawns the hook check and a status seed —
    // complete them cleanly so tests start from an idle service.
    for (var i = 0; i < ProcessRegistry.starts.length; i++)
      ProcessRegistry.starts[i].process.finish(0)
    ProcessRegistry.reset()
  }

  function cleanup() {
    service.destroy()
    service = null
  }

  function lastStart() {
    return ProcessRegistry.starts[ProcessRegistry.starts.length - 1]
  }

  function compareArgs(start, expected) {
    compare(JSON.stringify(start.command.slice(1)), JSON.stringify(expected))
  }

  function test_set_color_is_optimistic() {
    service.setColor("#123456")
    compare(service.color, "#123456")
    compare(service.followTheme, false)
    compare(service.on, true)
    compareArgs(lastStart(), ["set-color", "#123456"])
  }

  function test_toggle_sends_on_off() {
    service.setOn(false)
    compare(service.on, false)
    compareArgs(lastStart(), ["off"])
  }

  function test_slider_flood_coalesces_latest_wins() {
    service.setBrightness(30, false)
    service.setBrightness(50, false)
    service.setBrightness(70, false)
    compare(ProcessRegistry.starts.length, 1)
    compareArgs(ProcessRegistry.starts[0], ["brightness", "30", "--no-save"])
    ProcessRegistry.starts[0].process.finish(0)
    compare(ProcessRegistry.starts.length, 2)
    compareArgs(lastStart(), ["brightness", "70", "--no-save"])
  }

  function test_release_persists_without_no_save() {
    service.setBrightness(80, true)
    compareArgs(lastStart(), ["brightness", "80"])
  }

  function test_failed_command_flags_needs_setup() {
    service.toggle()
    lastStart().process.finish(1)
    compare(service.needsSetup, true)
    service.toggle()
    lastStart().process.finish(0)
    compare(service.needsSetup, false)
  }

  function test_hook_check_exit_code_mapping() {
    service.checkThemeHook()
    lastStart().process.finish(1)
    compare(service.themeHookInstalled, false)
    compare(service.themeHookStale, false)

    service.checkThemeHook()
    lastStart().process.finish(2)
    compare(service.themeHookInstalled, true)
    compare(service.themeHookStale, true)

    service.checkThemeHook()
    lastStart().process.finish(0)
    compare(service.themeHookInstalled, true)
    compare(service.themeHookStale, false)
  }

  function test_state_file_load() {
    FileViewRegistry.views[0].simulate(JSON.stringify({
      on: false, color: "#ABCDEF", hue: 210, brightness: 40,
      follow_theme: true, presets: ["#111111"]
    }))
    compare(service.on, false)
    compare(service.color, "#ABCDEF")
    compare(service.hue, 210)
    compare(service.brightness, 40)
    compare(service.followTheme, true)
    compare(service.presets.length, 1)
    verify(service.stateLoaded)
  }

  function test_torn_state_write_is_ignored() {
    FileViewRegistry.views[0].simulate('{"on": fal')
    compare(service.color, "#FF6600")
    compare(service.stateLoaded, false)
  }

  function test_device_list_refresh_parses_json() {
    service.refreshDevices()
    lastStart().process.stdout.finish(
      '[{"name": "Board", "type": "Motherboard", "managed": true}]')
    compare(service.devicesModel.length, 1)
    compare(service.devicesModel[0].name, "Board")
    compare(service.devicesModel[0].managed, true)
  }

  function test_disabling_last_device_sends_none() {
    service.devicesModel = [{name: "Board", managed: true}]
    service.setDeviceEnabled("Board", false)
    compare(service.devicesModel[0].managed, false)
    compareArgs(lastStart(), ["set-device", "--none"])
  }

  function test_disabling_one_device_keeps_the_rest() {
    service.devicesModel = [
      {name: "Board", managed: true},
      {name: "Mouse", managed: true}
    ]
    service.setDeviceEnabled("Mouse", false)
    compareArgs(lastStart(), ["set-device", "Board"])
  }

  function test_follow_theme_command() {
    service.setFollowTheme(true)
    compare(service.followTheme, true)
    compareArgs(lastStart(), ["follow-theme", "on"])
  }
}
