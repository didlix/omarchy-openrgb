pragma Singleton
import QtQuick

// Test stub for the Quickshell singleton — just enough for Service.qml.
QtObject {
  function env(name) {
    return name === "HOME" ? "/stub-home" : ""
  }
}
