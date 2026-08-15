import QtQuick

// Test stub for Quickshell.Io.FileView: content is injected by tests via
// simulate() rather than read from disk.
QtObject {
  id: root

  property string path: ""
  property bool watchChanges: false
  property bool printErrors: true
  property string content: ""

  signal loaded()
  signal fileChanged()

  Component.onCompleted: FileViewRegistry.register(root)

  function text() {
    return content
  }

  function reload() {
    loaded()
  }

  // Test helper: set content and emit loaded, as a real file change would.
  function simulate(payload) {
    content = payload
    loaded()
  }
}
