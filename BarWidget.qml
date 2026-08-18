import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// macOS-style app menu bar: shows the focused window's menu strip (from the
// omarchy-global-menu-bridge snapshot) in the bar, with click-to-open popups
// and hover-to-switch submenus. The bar slot renders the strip; a separate
// PopupWindow hosts the open menu so clicking outside dismisses it.
BarWidget {
  id: root
  moduleName: "primo.global-menu"

  readonly property var dataLoaderItem: dataLoader.item
  readonly property var record: dataLoaderItem ? dataLoaderItem.record : null
  readonly property var menubar: dataLoaderItem ? dataLoaderItem.menubar : []
  readonly property string appIcon: dataLoaderItem ? dataLoaderItem.icon : ""
  readonly property string appName: dataLoaderItem ? dataLoaderItem.appName : ""

  property int openIndex: -1
  property var openEntry: null
  property string lastAppId: ""

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return ""
  }

  readonly property string appIconUrl: root.iconSource(root.appIcon)

  function setOpenIndex(index) {
    var opening = root.openIndex < 0 && index >= 0
    var closing = root.openIndex >= 0 && index < 0
    root.openEntry = (index >= 0 && entryRepeater && entryRepeater.itemAt) ? entryRepeater.itemAt(index) : null
    root.openIndex = index
    if (root.bar) {
      if (opening) root.bar.requestPopout(root)
      else if (closing && root.bar.activePopout === root) root.bar.releasePopout(root)
    }
    var pop = popupLoader.active ? popupLoader.item : null
    if (pop && pop.visible && pop.anchor) Qt.callLater(function() { pop.anchor.updateAnchor() })
  }

  function activate(item) {
    var action = item && item.action
    if (!action || !action.kind) return
    root.setOpenIndex(-1)
    var kind = action.kind
    if (kind === "exec") {
      Quickshell.execDetached(["sh", "-c", String(action.command || "")])
    } else if (kind === "hypr") {
      Quickshell.execDetached(["hyprctl", "dispatch", String(action.lua || "")])
    } else {
      Quickshell.execDetached(["omarchy-global-menu-bridge", "activate", String(item.id)])
    }
  }

  function syncOpenEntry() {
    if (root.openIndex >= 0) {
      if (root.openIndex >= root.menubar.length) {
        root.setOpenIndex(-1)
      } else {
        root.openEntry = entryRepeater.itemAt(root.openIndex)
        var pop = popupLoader.active ? popupLoader.item : null
        if (pop && pop.visible && pop.anchor) Qt.callLater(function() { pop.anchor.updateAnchor() })
      }
    }
  }

  onMenubarChanged: root.syncOpenEntry()

  Loader {
    id: dataLoader
    active: true
    source: Qt.resolvedUrl("GlobalMenuData.qml")
  }

  Connections {
    target: dataLoader.item
    function onRecordChanged() {
      var next = dataLoader.item ? dataLoader.item.appId : ""
      if (root.lastAppId !== "" && next !== root.lastAppId) root.setOpenIndex(-1)
      root.lastAppId = next
    }
  }

  function open(): void { if (root.menubar.length > 0 && root.openIndex < 0) root.setOpenIndex(0) }
  function close(): void { root.setOpenIndex(-1) }
  function toggle(): void {
    if (root.openIndex >= 0) root.setOpenIndex(-1)
    else if (root.menubar.length > 0) root.setOpenIndex(0)
  }

  IpcHandler {
    target: "primo.global-menu"

    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("toggle") }
  }

  implicitWidth: root.vertical ? root.barSize : stripRow.implicitWidth
  implicitHeight: root.barSize

  Item {
    id: strip
    anchors.fill: parent

    Row {
      id: stripRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Item {
        id: iconWrap
        visible: root.appIconUrl !== "" && !root.vertical
        width: Style.space(24)
        height: root.barSize
        implicitWidth: Style.space(24)

        Image {
          anchors.centerIn: parent
          width: Style.space(16)
          height: Style.space(16)
          source: root.appIconUrl
          sourceSize.width: Style.space(16) * Screen.devicePixelRatio
          sourceSize.height: Style.space(16) * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
      }

      Repeater {
        id: entryRepeater
        model: root.menubar
        delegate: entryComponent
      }
    }
  }

  Component {
    id: entryComponent

    Item {
      id: entry
      required property int index
      required property var modelData

      property bool hovered: false
      readonly property string label: String(entry.modelData && entry.modelData.label || "")
      readonly property bool isOpen: root.openIndex === entry.index
      readonly property bool highlighted: entry.hovered || entry.isOpen

      visible: !root.vertical
      implicitWidth: Math.max(Style.space(8), labelText.implicitWidth + Style.space(16))
      implicitHeight: root.barSize

      Rectangle {
        visible: entry.highlighted
        anchors.fill: parent
        radius: Style.space(3)
        color: entry.hovered ? Style.normalFill : Style.selectedFill
      }

      Text {
        id: labelText
        anchors.centerIn: parent
        text: entry.label
        color: entry.highlighted
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : (root.bar ? root.bar.barForeground : Color.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: {
          entry.hovered = true
          if (root.openIndex >= 0 && root.openIndex !== entry.index) root.setOpenIndex(entry.index)
        }
        onExited: entry.hovered = false
        onClicked: {
          if (root.openIndex === entry.index) root.setOpenIndex(-1)
          else root.setOpenIndex(entry.index)
        }
      }
    }
  }

  Loader {
    id: popupLoader
    active: root.openIndex >= 0
    sourceComponent: popupComponent
  }

  Component {
    id: popupComponent

    PopupWindow {
      id: menuPopup

      readonly property var menu: root.menubar[root.openIndex]
      readonly property var anchorItem: root.openEntry !== null ? root.openEntry : strip

      visible: true
      color: "transparent"
      implicitWidth: menuListLoader.item ? menuListLoader.item.listWidth : Style.space(160)
      implicitHeight: menuListLoader.item ? menuListLoader.item.implicitHeight : 0

      HyprlandFocusGrab {
        active: menuPopup.visible
        windows: (function() {
          var list = [menuPopup]
          if (menuPopup.anchorItem && menuPopup.anchorItem.QsWindow) list.push(menuPopup.anchorItem.QsWindow.window)
          var menu = menuListLoader.item
          if (menu && menu.openFlyouts) list = list.concat(menu.openFlyouts)
          return list
        })()
        onCleared: root.setOpenIndex(-1)
      }

      anchor {
        id: menuAnchor
        window: menuPopup.anchorItem && menuPopup.anchorItem.QsWindow
          ? menuPopup.anchorItem.QsWindow.window : null
        edges: Edges.Bottom | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.Slide

        onAnchoring: {
          var target = menuPopup.anchorItem
          if (!target || !target.QsWindow) return
          var win = target.QsWindow.window
          if (!win) return
          var rect = win.contentItem.mapFromItem(target, 0, 0, target.width, target.height)
          menuAnchor.rect.x = Math.round(rect.x)
          menuAnchor.rect.y = Math.round(rect.y)
          menuAnchor.rect.width = Math.round(rect.width)
          menuAnchor.rect.height = Math.round(rect.height)
        }
      }

      Rectangle {
        id: popupCard
        anchors.fill: parent
        radius: Style.space(6)
        color: Color.popups.background
        border.color: Color.popups.border
        border.width: Math.max(1, Style.space(1))
      }

      Loader {
        id: menuListLoader
        anchors.fill: popupCard
        anchors.margins: Style.space(4)
        source: "MenuList.qml"
        onLoaded: menuPopup.wireMenuList(item)
      }

      function wireMenuList(list) {
        if (!list) return
        list.fontFamily = root.bar ? root.bar.fontFamily : Style.font.family
        list.foreground = Color.popups.text
        list.selectedBackground = Color.menu.selectedBackground
        list.selectedText = Color.menu.selectedText
        list.separatorColor = Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.22)
        list.items = (menuPopup.menu && menuPopup.menu.items) ? menuPopup.menu.items : []
        list.activated.connect(function(item) { root.activate(item) })
      }

      onMenuChanged: if (menuListLoader.item) menuListLoader.item.items = (menuPopup.menu && menuPopup.menu.items) ? menuPopup.menu.items : []
    }
  }
}
