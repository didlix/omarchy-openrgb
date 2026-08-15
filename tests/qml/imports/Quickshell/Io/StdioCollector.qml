import QtQuick

// Test stub for Quickshell.Io.StdioCollector.
QtObject {
  property bool waitForEnd: false
  property string text: ""

  signal streamFinished()

  // Test helper: deliver a payload as the finished stream.
  function finish(payload) {
    text = payload
    streamFinished()
  }
}
