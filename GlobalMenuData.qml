import QtQuick
import Quickshell
import Quickshell.Io

// Watches the bridge's snapshot of the focused window's menu. The daemon
// owns the file; this component only discovers and parses it, so any record
// that appears in the state directory is rendered, whoever wrote it.
Item {
  id: root
  visible: false

  property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/global-menu"
  property string path: root.stateDir + "/active.json"
  property var record: null

  readonly property var menubar: record && Array.isArray(record.menubar) ? record.menubar : []
  readonly property string appId: record ? String(record.appId || "") : ""
  readonly property string appName: record ? String(record.appName || "") : ""
  readonly property string icon: record ? String(record.icon || "") : ""
  readonly property string title: record ? String(record.title || "") : ""
  readonly property string source: record ? String(record.source || "") : ""

  FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      console.warn("global-menu", "Ignoring bad menu record", root.path, e)
      root.record = null
    }
  }
}
