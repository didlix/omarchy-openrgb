import QtQuick
import Quickshell
import Quickshell.Io

// State and actions for RGB lighting. The single source of truth is
// ~/.local/state/omarchy-rgb/state.json, written by the bundled omarchy-rgb
// CLI and watched here, so keybindings, menu entries and this widget stay
// consistent. Actions are optimistic (properties update immediately) and
// commands are coalesced (one in flight, latest pending wins) to absorb
// slider drags.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string stateFile: home + "/.local/state/omarchy-rgb/state.json"
  readonly property string cli: pluginDir + "bin/omarchy-rgb"

  property bool stateLoaded: false
  // Every device OpenRGB can see, as {name, type, managed} — refreshed when
  // the popout opens, used by the DEVICES section's toggles.
  property var devicesModel: []
  property bool on: true
  property string color: "#FF6600"
  property int hue: 24
  property int brightness: 100
  property bool followTheme: true
  property var presets: []

  // True after a command exits non-zero — the CLI could not reach the
  // hardware, which almost always means `omarchy-rgb setup` hasn't run.
  property bool needsSetup: false

  // Whether the theme-set hook is installed — without it the follow-theme
  // toggle can't actually track anything, so the panel greys it out. Stale
  // means installed but older than the copy this plugin version ships, so
  // the panel can suggest a refresh. Re-checked every time the popout
  // opens, so installing or upgrading the hook is picked up without a
  // shell restart.
  property bool themeHookInstalled: true
  property bool themeHookStale: false
  function checkThemeHook() {
    if (!hookProc.running) hookProc.running = true
  }

  property var pendingCommand: null

  function loadState(payload) {
    try {
      var s = JSON.parse(payload)
      root.on = s.on === true
      root.color = String(s.color || root.color)
      if (isFinite(Number(s.hue))) root.hue = Number(s.hue)
      if (isFinite(Number(s.brightness))) root.brightness = Number(s.brightness)
      root.followTheme = s.follow_theme === true
      root.presets = s.presets instanceof Array ? s.presets : []
      root.stateLoaded = true
    } catch (e) {
      // partial write or missing file; the next change re-triggers a load
    }
  }

  // Only absolute commands go through here — latest-wins coalescing would
  // change the outcome of relative ones (toggle, brightness +N).
  function run(args) {
    if (proc.running) {
      root.pendingCommand = args
      return
    }
    proc.command = [cli].concat(args)
    proc.running = true
  }

  function setOn(value) {
    root.on = value
    run([value ? "on" : "off"])
  }

  function toggle() {
    setOn(!root.on)
  }

  function setColor(hex) {
    root.color = hex
    root.followTheme = false
    root.on = true
    run(["set-color", hex])
  }

  // Drags pass save=false (--no-save) so slider floods don't wear the
  // devices' onboard flash; the release event persists the final value.
  function setHue(value, save) {
    var hue = Math.round(value) % 360
    root.hue = hue
    root.color = String(Qt.hsva(hue / 360, 1, 1, 1))
    root.followTheme = false
    root.on = true
    run(save ? ["set-hue", String(hue)] : ["set-hue", String(hue), "--no-save"])
  }

  function setBrightness(value, save) {
    root.brightness = Math.round(value)
    run(save ? ["brightness", String(root.brightness)]
             : ["brightness", String(root.brightness), "--no-save"])
  }

  function setFollowTheme(value) {
    root.followTheme = value
    run(["follow-theme", value ? "on" : "off"])
  }

  function refreshDevices() {
    if (!devicesProc.running) devicesProc.running = true
  }

  // Full re-detection: restarts the OpenRGB server (the SDK protocol has no
  // rescan), then re-reads the device list. For hot-plugged hardware.
  property bool rescanning: false
  function rescanDevices() {
    if (rescanProc.running) return
    root.rescanning = true
    rescanProc.running = true
  }

  // Toggle whether a device is managed. Writes the explicit set of managed
  // device names; an empty selection is sent as --none (a bare empty list
  // means auto-detect on the CLI, which would silently re-enable a device).
  function setDeviceEnabled(name, enabled) {
    var names = []
    var model = devicesModel.slice()
    for (var i = 0; i < model.length; i++) {
      var dev = Object.assign({}, model[i])
      if (dev.name === name) dev.managed = enabled
      if (dev.managed === true) names.push(dev.name)
      model[i] = dev
    }
    root.devicesModel = model
    run(names.length > 0 ? ["set-device"].concat(names) : ["set-device", "--none"])
  }

  // Assign a device's follow-theme colour role (primary/secondary/accent).
  // Optimistic like everything else; the CLI relights if follow-theme is on.
  function setDeviceRole(name, role) {
    var model = devicesModel.slice()
    for (var i = 0; i < model.length; i++) {
      var dev = Object.assign({}, model[i])
      if (dev.name === name) dev.role = role
      model[i] = dev
    }
    root.devicesModel = model
    run(["device-role", name, role])
  }

  Process {
    id: hookProc
    // Exit 1: hook missing. Exit 2: installed but differs from the plugin's
    // shipped copy (an update changed it, or it's a hand-edited relic).
    command: ["sh", "-c",
      'dst="$HOME/.config/omarchy/hooks/theme-set.d/20-case-rgb"; ' +
      'test -x "$dst" || exit 1; cmp -s "$dst" "$1" || exit 2',
      "sh", root.pluginDir + "hooks/20-case-rgb"]
    onExited: function(exitCode) {
      root.themeHookInstalled = exitCode !== 1
      root.themeHookStale = exitCode === 2
    }
  }

  Process {
    id: rescanProc
    command: [root.cli, "rescan"]
    onExited: {
      root.rescanning = false
      root.refreshDevices()
    }
  }

  Process {
    id: devicesProc
    command: [root.cli, "list-devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.devicesModel = parsed instanceof Array ? parsed : []
        } catch (e) {
          root.devicesModel = []
        }
      }
    }
  }

  Process {
    id: proc
    onExited: function(exitCode) {
      root.needsSetup = exitCode !== 0
      if (root.pendingCommand !== null) {
        var next = root.pendingCommand
        root.pendingCommand = null
        root.run(next)
      }
    }
  }

  FileView {
    path: root.stateFile
    watchChanges: true
    printErrors: false
    onLoaded: root.loadState(text())
    // text() is stale inside the change signal; reload routes through onLoaded.
    onFileChanged: reload()
  }

  // Seed the state file on first ever run so the watch has something to load
  // (status always exits 0 and writes the file).
  Component.onCompleted: {
    checkThemeHook()
    if (!stateLoaded) run(["status"])
  }
}
