import QtQuick
import Quickshell.Io
import Quickshell.Widgets
import "../../components"
import "ShelfModel.js" as ShelfModel

// The Shelf: files, images, links and text parked on the island. Memory-only by
// design — a shell restart (or reboot) empties it. Opened from the control
// center's Shelf chip, `omarchy-shell lanta.island shelf`, or by parking the
// current clipboard with `shelfAdd`.
ListPicker {
  id: shelf
  placeholder: "Search shelf"
  emptyText: shelf.host.shelf.length ? "Nothing matches" : "Drag files, links or text here"
  // Grid of tiles: wide enough for a thumbnail and a name, tall enough for both.
  rowHeight: 96
  visibleRows: 4
  minRows: 2
  columns: 3
  // The tiles are cards, so they draw their own selection.
  showHighlight: false
  items: {
    var q = query.trim().toLowerCase()
    if (!q) return host.shelf
    return host.shelf.filter(function(item) { return ShelfModel.searchText(item).indexOf(q) !== -1 })
  }
  onChosen: function(entry) { copy(entry) }
  // Esc closes the tile menu first; everything else is the picker's own.
  onKeyFilter: function(event) {
    if (event.key === Qt.Key_Escape && shelf.menuEntry !== null) {
      shelf.closeMenu()
      event.accepted = true
    }
  }
  onActiveChanged: if (!active) closeMenu()

  readonly property var glyphs: ({ image: "󰋩", file: "󰈔", url: "󰖟", text: "󰆒" })

  // ---------- Actions ----------
  //
  // Click a tile to copy it, drag it out to hand it to another app, right click
  // it for the little menu of actions.

  // Copies the item, not just its text: an image goes back as an image, a file
  // as a file uri-list, so it can be pasted where it came from.
  Process { id: copier }
  function copy(row) {
    if (!row) return
    if (row.kind === "image")
      copier.command = ["bash", "-c", 'wl-copy --type "$1" < "$2"', "--", String(row.mime || "image/png"), String(row.path || "")]
    else if (row.kind === "file")
      copier.command = ["bash", "-c", 'printf "%s\\n" "$1" | wl-copy --type text/uri-list', "--", fileUri(row.path)]
    else
      copier.command = ["bash", "-c", 'printf "%s" "$1" | wl-copy', "--", String(row.text || "")]
    copier.startDetached()
  }

  Process { id: opener }
  function open(row) {
    if (!row) return
    if (row.kind === "image" || row.kind === "file") opener.command = ["xdg-open", String(row.path || "")]
    else if (row.kind === "url") opener.command = ["xdg-open", String(row.text || "")]
    else { copy(row); return }
    opener.startDetached()
  }

  function remove(row) { if (row) shelf.host.shelfRemove(row) }

  // Text is the one payload a file manager cannot take, so offer to write it
  // out as a .txt in Downloads instead.
  Process { id: saver }
  function saveText(row) {
    if (!row || row.kind !== "text") return
    var name = "shelf-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".txt"
    saver.command = ["bash", "-c", 'printf "%s" "$1" > "$2"', "--",
                     String(row.text || ""), shelf.host.home + "/Downloads/" + name]
    saver.startDetached()
  }

  // What the platform drag hands over. Files and images travel as a
  // text/uri-list so any app can take them as a file. Plain text offers only
  // text/* (adding a uri-list would let a target paste the path instead), while
  // a link offers both because apps differ on which one they prefer.
  function fileUri(path) {
    var parts = String(path || "").split("/")
    for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    return "file://" + parts.join("/")
  }
  function mimeFor(row) {
    if (!row) return ({})
    if (row.kind === "image" || row.kind === "file")
      return ({ "text/uri-list": fileUri(row.path) + "\r\n" })
    var text = String(row.text || "")
    if (row.kind === "url")
      return ({ "text/uri-list": text + "\r\n", "text/plain": text, "text/plain;charset=utf-8": text })
    return ({ "text/plain": text, "text/plain;charset=utf-8": text })
  }

  // ---------- Tile menu ----------
  property var menuEntry: null
  property real menuX: 0
  property real menuY: 0
  function openMenu(entry, x, y) {
    menuEntry = entry
    menuX = x
    menuY = y
  }
  function closeMenu() { menuEntry = null }

  readonly property var menuActions: {
    var e = menuEntry
    if (!e) return []
    var actions = []
    if (e.kind === "image") {
      actions.push({ id: "copy", icon: "󰆏", label: "Copy image" })
      actions.push({ id: "open", icon: "󰋩", label: "Open" })
    } else if (e.kind === "file") {
      actions.push({ id: "copy", icon: "󰆏", label: "Copy file" })
      actions.push({ id: "open", icon: "󰈔", label: "Open" })
    } else if (e.kind === "url") {
      actions.push({ id: "copy", icon: "󰆏", label: "Copy link" })
      actions.push({ id: "open", icon: "󰖟", label: "Open link" })
    } else {
      actions.push({ id: "copy", icon: "󰆏", label: "Copy text" })
      actions.push({ id: "save", icon: "󰈔", label: "Save as .txt" })
    }
    actions.push({ id: "remove", icon: "󰅖", label: "Remove from shelf" })
    if (shelf.host.shelf.length > 1) actions.push({ id: "clear", icon: "󰩹", label: "Clear shelf" })
    return actions
  }
  function runMenuAction(id) {
    var e = menuEntry
    if (id === "copy") copy(e)
    else if (id === "open") open(e)
    else if (id === "save") saveText(e)
    else if (id === "remove") remove(e)
    else if (id === "clear") shelf.host.shelfClear()
    closeMenu()
  }

  row: Component {
    Item {
      id: tile
      property var entry: ({})
      property bool selected: false
      readonly property bool isImage: !!entry && entry.kind === "image"
      readonly property string glyph: shelf.glyphs[entry ? entry.kind : ""] || shelf.glyphs.text

      // Every tile is a card, so an empty cell reads as empty space instead of
      // a stray icon and the selected one does not look larger than the rest.
      Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 3
        radius: 12
        color: tile.selected
          ? shelf.host.withAlpha(shelf.host.colorAccent, 0.16)
          : shelf.host.withAlpha(shelf.host.colorText, 0.05)
        border.width: 1
        border.color: tile.selected
          ? shelf.host.withAlpha(shelf.host.colorAccent, 0.6)
          : shelf.host.withAlpha(shelf.host.colorText, 0.08)
        Behavior on color { ColorAnimation { duration: 130 * shelf.host.motionScale; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 130 * shelf.host.motionScale; easing.type: Easing.OutQuad } }

        ClippingRectangle {
          id: thumb
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 9
          width: 44
          height: 44
          radius: 10
          color: shelf.host.withAlpha(shelf.host.colorText, 0.08)
          Image {
            id: shelfThumb
            anchors.fill: parent
            source: tile.isImage && tile.entry.path ? "file://" + tile.entry.path : ""
            sourceSize.width: 88
            sourceSize.height: 88
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
          }
          Text {
            anchors.centerIn: parent
            visible: !tile.isImage || shelfThumb.status !== Image.Ready
            text: tile.glyph
            color: shelf.host.colorMuted
            font.family: shelf.host.fontFamily
            font.pixelSize: 20
          }
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: thumb.bottom
          anchors.topMargin: 5
          width: parent.width - 14
          horizontalAlignment: Text.AlignHCenter
          text: String(tile.entry ? tile.entry.name || "" : "")
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          maximumLineCount: 1
          color: shelf.host.colorText
          font.family: "Adwaita Sans"
          font.pixelSize: 11
        }
      }

      // Left: click copies the item, drag pulls it out to another app. The
      // gesture drags an invisible proxy, so the card itself never moves; the
      // platform then takes the payload over for the drop into the other app.
      Item {
        id: dragProxy
        anchors.fill: parent
        Drag.active: dragArea.drag.active
        Drag.dragType: Drag.Automatic
        // Copy or link only: Move would let a file manager relocate the file
        // the shelf is only pointing at.
        Drag.supportedActions: Qt.CopyAction | Qt.LinkAction
        Drag.mimeData: shelf.mimeFor(tile.entry)
        Drag.hotSpot: Qt.point(width / 2, height / 2)
        Drag.onDragStarted: shelf.host.tileDragging = true
        Drag.onDragFinished: function(dropAction) {
          shelf.host.tileDragging = false
          // The other app took it: get the shelf out of the way again.
          if (dropAction !== Qt.IgnoreAction) shelf.host.view = "rest"
        }
      }
      MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        drag.target: dragProxy
        // Snapshot the card so the drag has a ghost under the cursor. (The
        // island's input region shrinks in onDragStarted instead of here --
        // changing it during the press cancels the drag gesture.)
        onPressed: {
          card.grabToImage(function(result) { dragProxy.Drag.imageSource = result.url })
        }
        onReleased: shelf.host.tileDragging = false
        onCanceled: shelf.host.tileDragging = false
        onClicked: shelf.copy(tile.entry)
      }

      // Right: the tile's menu.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: function(mouse) {
          var p = tile.mapToItem(shelf, mouse.x, mouse.y)
          shelf.openMenu(tile.entry, p.x, p.y)
        }
      }

      // Remove button, tucked inside the card's rounded corner.
      Text {
        id: removeButton
        visible: tile.selected
        anchors.right: card.right
        anchors.top: card.top
        anchors.margins: 5
        text: "󰅖"
        color: removeMouse.containsMouse ? shelf.host.colorText : shelf.host.colorMuted
        font.family: shelf.host.fontFamily
        font.pixelSize: 12
        MouseArea {
          id: removeMouse
          anchors.fill: parent
          anchors.margins: -7
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: shelf.remove(tile.entry)
        }
      }
    }
  }

  // The tile menu: a small card of actions at the right click, kept inside the
  // shelf. Clicking anywhere else dismisses it.
  Item {
    id: contextMenu
    anchors.fill: parent
    visible: shelf.menuEntry !== null
    z: 50

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: shelf.closeMenu()
    }

    Rectangle {
      id: menuCard
      width: 202
      height: menuColumn.implicitHeight + 12
      x: Math.max(6, Math.min(shelf.menuX, contextMenu.width - width - 6))
      y: Math.max(6, Math.min(shelf.menuY, contextMenu.height - height - 6))
      radius: 12
      color: shelf.host.colorBackground
      border.width: 1
      border.color: shelf.host.withAlpha(shelf.host.colorText, 0.14)

      Column {
        id: menuColumn
        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        Repeater {
          model: shelf.menuActions
          delegate: Rectangle {
            required property var modelData
            width: menuColumn.width
            height: 32
            radius: 8
            color: actionMouse.containsMouse ? shelf.host.withAlpha(shelf.host.colorText, 0.1) : "transparent"
            Row {
              anchors.left: parent.left
              anchors.leftMargin: 9
              anchors.verticalCenter: parent.verticalCenter
              spacing: 9
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.icon
                color: shelf.host.colorMuted
                font.family: shelf.host.fontFamily
                font.pixelSize: 15
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: shelf.host.colorText
                font.family: "Adwaita Sans"
                font.pixelSize: 13
              }
            }
            MouseArea {
              id: actionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: shelf.runMenuAction(modelData.id)
            }
          }
        }
      }
    }
  }
}
