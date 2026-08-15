import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// RGB Lighting bar widget: icon tinted with the current colour, popout with
// on/off, preset swatches, hue + brightness sliders, and follow-theme.
// Default manageIpc gives `omarchy-shell didlix.case-rgb open/close/toggle`.
Panel {
  id: root
  moduleName: "didlix.case-rgb"
  ipcTarget: "didlix.case-rgb"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Whether the popout is showing the DEVICE ROLES view instead of the
  // main controls. Always reopens on the main view.
  property bool rolesOpen: false

  onOpenedChanged: if (opened) {
    rolesOpen = false
    rgb.refreshDevices()
    rgb.checkThemeHook()
  }

  Service {
    id: rgb
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌵"
    foreground: rgb.on ? rgb.color : Qt.darker(root.barForeground, 1.55)
    tooltipText: rgb.on ? "RGB lighting" : "RGB lighting (off)"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) rgb.toggle()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    // Clip and scroll when the device list outgrows the card.
    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

      // Stale-hook callout: blockquote-style accent bar on the left, so it
      // reads as a notice rather than another bordered control. Sits above
      // the view switch so it shows in both views.
      BorderSurface {
        visible: rgb.themeHookStale
        width: parent.width
        implicitHeight: staleText.implicitHeight + Style.space(16)
        color: Qt.alpha(Color.accent, 0.08)
        borderSpec: Border.flat(Color.accent, "0 0 0 3")

        Text {
          id: staleText
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(8)
          text: "Theme hook update available — re-run `omarchy-rgb setup`."
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }

      // Main view — hidden while the DEVICE ROLES view is open.
      Column {
        id: mainView
        visible: !root.rolesOpen
        width: parent.width
        spacing: Style.space(12)

      Text {
        visible: rgb.needsSetup
        width: parent.width
        text: "Can't reach OpenRGB — run the plugin's `omarchy-rgb setup` (see README)."
        color: root.bar ? root.bar.urgent : Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Toggle {
        width: parent.width
        label: "RGB lighting"
        checked: rgb.on
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: rgb.toggle()
      }

      PanelSectionHeader {
        text: "PRESETS"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Grid {
        columns: 4
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(10)
        anchors.horizontalCenter: parent.horizontalCenter

        Repeater {
          model: rgb.presets
          BorderSurface {
            id: swatch
            required property var modelData
            readonly property bool active: rgb.on && String(modelData).toUpperCase() === String(rgb.color).toUpperCase()
            width: Style.space(48)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: String(modelData)
            borderSpec: Border.flat(active ? Color.accent : root.dim, active ? Math.max(2, Style.space(2)) : 1)
            scale: swatchMouse.containsMouse ? 1.08 : 1.0

            Behavior on scale {
              NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
            }

            MouseArea {
              id: swatchMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: rgb.setColor(String(swatch.modelData))
            }
          }
        }
      }

      PanelSectionHeader {
        text: "HUE"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      PanelSlider {
        id: hueSlider
        width: parent.width
        bar: root.bar
        minimum: 0
        maximum: 359
        step: 5
        integer: true
        value: rgb.hue
        fillColor: Qt.hsva(hueSlider.liveValue / 360, 1, 1, 1)
        knobColor: Qt.hsva(hueSlider.liveValue / 360, 1, 1, 1)
        onMoved: function(value) { rgb.setHue(value, false) }
        onReleased: function(value) { rgb.setHue(value, true) }
      }

      PanelSectionHeader {
        text: "BRIGHTNESS"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      PanelSlider {
        width: parent.width
        bar: root.bar
        minimum: 0
        maximum: 100
        step: 5
        integer: true
        value: rgb.brightness
        onMoved: function(value) { rgb.setBrightness(value, false) }
        onReleased: function(value) { rgb.setBrightness(value, true) }
      }

      Toggle {
        width: parent.width
        label: "Follow theme"
        description: rgb.themeHookInstalled
          ? "Colour tracks the theme accent"
          : "Theme hook not installed — run `omarchy-rgb setup --with-theme-hook`"
        enabled: rgb.themeHookInstalled
        opacity: rgb.themeHookInstalled ? 1.0 : 0.4
        checked: rgb.followTheme
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: rgb.setFollowTheme(!rgb.followTheme)
      }

      Item {
        width: parent.width
        implicitHeight: devicesHeader.implicitHeight

        PanelSectionHeader {
          id: devicesHeader
          text: "DEVICES"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        PanelActionButton {
          id: rescanButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑐"
          tooltipText: rgb.rescanning ? "Rescanning…" : "Rescan for new devices"
          enabled: !rgb.rescanning
          opacity: rgb.rescanning ? 0.4 : 1.0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: rgb.rescanDevices()
        }

        PanelActionButton {
          anchors.right: rescanButton.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰒓"
          tooltipText: "Device colour roles"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.rolesOpen = true
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: rgb.devicesModel
          Toggle {
            required property var modelData
            width: parent.width
            label: String(modelData.name || "")
            description: String(modelData.type || "")
            checked: modelData.managed === true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: rgb.setDeviceEnabled(String(modelData.name || ""), modelData.managed !== true)
          }
        }

        Text {
          visible: rgb.devicesModel.length === 0
          width: parent.width
          text: "No devices found — is the OpenRGB server running?"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
      }

      // DEVICE ROLES view — the cog's own page: per managed device, which
      // theme colour it follows while follow-theme is on.
      Column {
        id: rolesView
        visible: root.rolesOpen
        width: parent.width
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: rolesHeader.implicitHeight

          PanelSectionHeader {
            id: rolesHeader
            text: "DEVICE ROLES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          PanelActionButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰁍"
            tooltipText: "Back"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.rolesOpen = false
          }
        }

        Text {
          width: parent.width
          text: "Which theme colour each device follows while Follow theme is on: the theme's primary colour, its secondary, or the raw accent."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: !rgb.followTheme
          width: parent.width
          text: "Follow theme is off — roles take effect when it's re-enabled."
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: rgb.devicesModel
          Column {
            id: roleRow
            required property var modelData
            readonly property bool multiZone: (modelData.zones instanceof Array) && modelData.zones.length > 1
            visible: modelData.managed === true
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: String(roleRow.modelData.name || "")
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            ButtonGroup {
              options: ["primary", "secondary", "accent"]
              value: String(roleRow.modelData.role || "primary")
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              focusable: false
              onChanged: function(value) {
                rgb.setDeviceRole(String(roleRow.modelData.name || ""), value)
              }
            }

            // Zones inherit the device role until given their own; shown
            // indented, only when the device actually has several zones.
            Repeater {
              model: roleRow.multiZone ? roleRow.modelData.zones : []
              Column {
                id: zoneRow
                required property var modelData
                width: parent.width
                spacing: Style.space(4)

                Text {
                  width: parent.width
                  leftPadding: Style.space(14)
                  text: String(zoneRow.modelData.name || "")
                  elide: Text.ElideRight
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                ButtonGroup {
                  x: Style.space(14)
                  options: ["primary", "secondary", "accent"]
                  value: String(zoneRow.modelData.role || roleRow.modelData.role || "primary")
                  foreground: root.foreground
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  focusable: false
                  onChanged: function(value) {
                    rgb.setDeviceRole(String(roleRow.modelData.name || "") + "/" + String(zoneRow.modelData.name || ""), value)
                  }
                }
              }
            }
          }
        }

        Text {
          visible: !rgb.devicesModel.some(function(d) { return d.managed === true })
          width: parent.width
          text: "No managed devices — enable one under DEVICES first."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
      }
    }
  }
}
