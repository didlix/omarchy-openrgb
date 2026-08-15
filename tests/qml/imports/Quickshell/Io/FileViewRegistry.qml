pragma Singleton
import QtQuick

// Records every FileView so tests can push simulated file contents into
// the service's state watch.
QtObject {
  property var views: []

  function register(view) {
    views = views.concat([view])
  }

  function reset() {
    views = []
  }
}
