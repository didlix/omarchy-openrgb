pragma Singleton
import QtQuick

// Records every Process start (the process and a snapshot of its command),
// so tests can assert which commands the service would have spawned and
// simulate their completion.
QtObject {
  property var starts: []

  function register(process) {
    starts = starts.concat([{process: process, command: process.command.slice()}])
  }

  function reset() {
    starts = []
  }
}
