import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Case RGB bar widget: icon tinted with the current colour, popout with
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

  onOpenedChanged: if (opened) rgb.refreshDevices()

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
        description: "Colour tracks the theme accent"
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
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: rgb.devicesModel
          Item {
            id: deviceRow
            required property var modelData
            // Roles only mean something for a managed device while
            // follow-theme is on; otherwise the chip hides.
            readonly property bool showRole: modelData.managed === true && rgb.followTheme
            readonly property var roleOrder: ["primary", "secondary", "accent"]
            width: parent.width
            implicitHeight: deviceToggle.implicitHeight

            Toggle {
              id: deviceToggle
              anchors.left: parent.left
              anchors.right: parent.right
              label: String(deviceRow.modelData.name || "")
              description: String(deviceRow.modelData.type || "")
              checked: deviceRow.modelData.managed === true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: rgb.setDeviceEnabled(String(deviceRow.modelData.name || ""), deviceRow.modelData.managed !== true)
            }

            // Role chip: click to cycle which theme colour this device follows.
            BorderSurface {
              visible: deviceRow.showRole
              anchors.right: parent.right
              anchors.rightMargin: Style.space(56)
              anchors.verticalCenter: parent.verticalCenter
              width: roleText.implicitWidth + Style.space(14)
              height: roleText.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: "transparent"
              borderSpec: Border.flat(root.dim, 1)

              Text {
                id: roleText
                anchors.centerIn: parent
                text: String(deviceRow.modelData.role || "primary")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var current = deviceRow.roleOrder.indexOf(String(deviceRow.modelData.role || "primary"))
                  var next = deviceRow.roleOrder[(current + 1) % deviceRow.roleOrder.length]
                  rgb.setDeviceRole(String(deviceRow.modelData.name || ""), next)
                }
              }
            }
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
    }
  }
}
