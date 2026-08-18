import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One vertical menu, rendered from the bridge snapshot schema (a list of
// items: separators, leaves, and submenus). Submenu rows open a hover-driven
// flyout to the right, macOS-style. Self-nesting via a Loader that loads this
// same file, so arbitrary menu depth works.
//
// Hover bookkeeping: every row reports into `hoveredRows`, and `hovered` also
// folds in any open submenu flyout, so a parent row stays open while the
// cursor is anywhere inside its flyout (including deep nesting).
Item {
  id: root

  property var items: []
  property var bar: null
  property string fontFamily: Style.font.family
  property color foreground: Color.popups.text
  property color dimColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color separatorColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
  property int rowHeight: Math.max(Style.space(26), Style.spacing.popupRowHeight)
  property int separatorHeight: Style.space(9)
  property int iconSize: Style.space(16)
  property int indicatorSize: Style.space(18)
  property int chevronWidth: Style.space(12)
  property int rowPaddingX: Style.spacing.rowPaddingX
  property int itemSpacing: Style.space(8)
  property int maxWidth: Style.space(340)
  property int minWidth: Style.space(160)

  signal activated(var item)

  property int hoveredRows: 0
  readonly property bool hovered: root.hoveredRows > 0
    || (flyoutLoader.active && flyoutLoader.item && flyoutLoader.item.hovered === true)

  readonly property var openFlyouts: {
    var result = []
    var fly = flyoutLoader.active ? flyoutLoader.item : null
    if (fly) {
      result.push(fly)
      var inner = fly.submenuList
      if (inner) result = result.concat(inner.openFlyouts)
    }
    return result
  }

  // One submenu is "active" at a time. Un-hovering a row closes its flyout
  // after a beat so the cursor can pass through the gap to the flyout.
  property var activeFlyoutRow: null
  property bool closePending: false
  property bool flyoutEverShown: false

  Timer {
    id: closeTimer
    interval: 180
    onTriggered: {
      root.closePending = false
      root.activeFlyoutRow = null
    }
  }

  function requestOpen(row) {
    root.flyoutEverShown = true
    closeTimer.stop()
    root.closePending = false
    if (root.activeFlyoutRow !== row) root.activeFlyoutRow = row
  }

  function requestClose(row) {
    if (row !== root.activeFlyoutRow) return
    if (!root.closePending) {
      root.closePending = true
      closeTimer.start()
    }
  }

  function cancelClose() {
    root.closePending = false
    closeTimer.stop()
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return ""
  }

  function measure(label) {
    metrics.text = String(label || "")
    return metrics.advanceWidth
  }

  TextMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  function contentWidthFor(item) {
    if (!item) return 0
    if (item.type === "separator") return 0
    var w = 0
    var check = String(item.checkState || "none")
    if (check !== "none") w += root.indicatorSize + root.itemSpacing
    if (String(item.icon || "") !== "") w += root.iconSize + root.itemSpacing
    w += root.measure(item.label)
    if (item.type === "menu" && item.items && item.items.length > 0) w += root.chevronWidth + root.itemSpacing
    return w
  }

  property int listWidth: root.minWidth

  function recomputeWidth() {
    var items = root.items || []
    var widest = 0
    for (var i = 0; i < items.length; i++) widest = Math.max(widest, root.contentWidthFor(items[i]))
    root.listWidth = Math.max(root.minWidth, Math.min(root.maxWidth, widest + root.rowPaddingX * 2))
  }

  onFontFamilyChanged: root.recomputeWidth()
  onItemsChanged: {
    root.hoveredRows = 0
    root.activeFlyoutRow = null
    root.recomputeWidth()
  }

  onActiveFlyoutRowChanged: {
    var fly = flyoutLoader.active ? flyoutLoader.item : null
    if (fly && fly.anchor) Qt.callLater(function() { fly.anchor.updateAnchor() })
  }

  Connections {
    target: flyoutLoader.item
    enabled: flyoutLoader.active
    function onHoveredChanged() {
      var fly = flyoutLoader.item
      if (fly && fly.hovered) root.cancelClose()
      else if (root.activeFlyoutRow && !root.activeFlyoutRow.hovered) root.requestClose(root.activeFlyoutRow)
    }
  }

  implicitWidth: root.listWidth
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: root.listWidth
    spacing: 1

    Repeater {
      model: root.items
      delegate: rowDelegate
    }
  }

  Component {
    id: rowDelegate

    Item {
      id: row
      required property var modelData
      required property int index

      readonly property var item: row.modelData
      readonly property bool isSeparator: item.type === "separator"
      readonly property bool isSubmenu: item.type === "menu" && item.items && item.items.length > 0
      readonly property bool isEnabled: item.enabled !== false
      readonly property string checkState: String(item.checkState || "none")
      readonly property bool hasIndicator: checkState !== "none"
      readonly property bool hasIcon: String(item.icon || "") !== ""

      readonly property real leftConsumed: root.rowPaddingX
        + (row.hasIndicator ? root.indicatorSize + root.itemSpacing : 0)
        + (row.hasIcon ? root.iconSize + root.itemSpacing : 0)
      readonly property real rightReserved: root.rowPaddingX
        + (row.isSubmenu ? root.chevronWidth + root.itemSpacing : 0)

      property bool hovered: false

      width: root.listWidth
      height: row.isSeparator ? root.separatorHeight : root.rowHeight

      Rectangle {
        visible: !row.isSeparator
        anchors.fill: parent
        radius: Style.space(3)
        color: row.hovered ? root.selectedBackground : "transparent"
      }

      Rectangle {
        visible: row.isSeparator
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.rowPaddingX
        anchors.rightMargin: root.rowPaddingX
        height: 1
        color: root.separatorColor
      }

      Text {
        visible: row.hasIndicator && !row.isSeparator
        width: root.indicatorSize
        anchors.left: parent.left
        anchors.leftMargin: root.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: row.checkState === "check" ? "\uf00c" : (row.checkState === "radio" ? "\u25cf" : "")
        color: row.hovered ? root.selectedText : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Image {
        visible: row.hasIcon && !row.isSeparator
        anchors.left: parent.left
        anchors.leftMargin: root.rowPaddingX + (row.hasIndicator ? root.indicatorSize + root.itemSpacing : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSize
        height: root.iconSize
        source: root.iconSource(row.item.icon)
        sourceSize.width: root.iconSize * Screen.devicePixelRatio
        sourceSize.height: root.iconSize * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }

      Text {
        id: labelText
        visible: !row.isSeparator
        anchors.left: parent.left
        anchors.leftMargin: row.leftConsumed
        anchors.right: parent.right
        anchors.rightMargin: row.rightReserved
        anchors.verticalCenter: parent.verticalCenter
        text: row.item.label || ""
        color: row.isEnabled ? (row.hovered ? root.selectedText : root.foreground) : root.dimColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        visible: row.isSubmenu
        anchors.right: parent.right
        anchors.rightMargin: root.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        text: "\u203a"
        color: row.hovered ? root.selectedText : root.dimColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        visible: !row.isSeparator
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: row.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: row.hovered = true
        onExited: row.hovered = false
        onClicked: {
          if (row.isSubmenu || !row.isEnabled) return
          root.activated(row.item)
        }
      }

      onHoveredChanged: {
        if (row.hovered) root.hoveredRows += 1
        else root.hoveredRows = Math.max(0, root.hoveredRows - 1)
        if (!row.isSubmenu) return
        if (row.hovered) root.requestOpen(row)
        else root.requestClose(row)
      }
    }
  }

  Loader {
    id: flyoutLoader
    active: true

    sourceComponent: Component {
      PopupWindow {
        id: flyout

        readonly property var anchorRow: root.activeFlyoutRow !== null ? root.activeFlyoutRow : root
        readonly property var submenuItems: root.activeFlyoutRow && root.activeFlyoutRow.item && root.activeFlyoutRow.item.items
          ? root.activeFlyoutRow.item.items : []
        readonly property bool hovered: flyout.hoveredViaCard || (flyoutList.item ? flyoutList.item.hovered === true : false)
        readonly property var submenuList: flyoutList.item
        property bool hoveredViaCard: false

        onSubmenuItemsChanged: if (flyoutList.item) flyoutList.item.items = flyout.submenuItems

        visible: root.activeFlyoutRow != null
        color: "transparent"
        implicitWidth: flyoutList.item ? flyoutList.item.listWidth : root.minWidth
        implicitHeight: flyoutList.item ? flyoutList.item.implicitHeight : 0

        anchor {
          id: flyoutAnchor
          window: flyout.anchorRow && flyout.anchorRow.QsWindow
            ? flyout.anchorRow.QsWindow.window : null
          edges: Edges.Right | Edges.Top
          gravity: Edges.Right | Edges.Bottom
          adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide

          onAnchoring: {
            var target = flyout.anchorRow
            if (!target || !target.QsWindow) return
            var win = target.QsWindow.window
            if (!win) return
            var rect = win.contentItem.mapFromItem(target, 0, 0, target.width, target.height)
            flyoutAnchor.rect.x = Math.round(rect.x)
            flyoutAnchor.rect.y = Math.round(rect.y)
            flyoutAnchor.rect.width = Math.round(rect.width)
            flyoutAnchor.rect.height = Math.round(rect.height)
          }
        }

        Rectangle {
          id: flyoutCard
          anchors.fill: parent
          radius: Style.space(6)
          color: Color.popups.background
          border.color: Color.popups.border
          border.width: Math.max(1, Style.space(1))

          HoverHandler {
            id: flyoutCardHover
            onHoveredChanged: flyout.hoveredViaCard = flyoutCardHover.hovered
          }
        }

        Loader {
          id: flyoutList
          active: root.flyoutEverShown
          anchors.fill: flyoutCard
          anchors.margins: Style.space(4)
          source: "MenuList.qml"
          onLoaded: {
            var list = item
            list.fontFamily = root.fontFamily
            list.foreground = root.foreground
            list.dimColor = root.dimColor
            list.selectedBackground = root.selectedBackground
            list.selectedText = root.selectedText
            list.separatorColor = root.separatorColor
            list.items = flyout.submenuItems
            list.activated.connect(function(item) { root.activated(item) })
          }
        }
      }
    }
  }
}
