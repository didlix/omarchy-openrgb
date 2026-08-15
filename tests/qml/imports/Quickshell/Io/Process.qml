import QtQuick

// Test stub for Quickshell.Io.Process: setting running to true registers
// the start; nothing actually executes until a test calls finish().
QtObject {
  id: root

  property var command: []
  property bool running: false
  property var stdout: null

  signal exited(int exitCode)

  onRunningChanged: if (running) ProcessRegistry.register(root)

  // Test helper: complete the process with the given exit code.
  function finish(exitCode) {
    running = false
    exited(exitCode)
  }
}
