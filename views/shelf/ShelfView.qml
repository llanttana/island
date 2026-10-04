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
  // Grid of tiles: small cards so a good number of items fit at once.
  rowHeight: 78
  visibleRows: 5
  minRows: 2
  columns: 4
  // The tiles are cards, so they draw their own selection.
  showHighlight: false
  items: {
    var q = query.trim().toLowerCase()
    if (!q) return host.shelf
    return host.shelf.filter(function(item) { return ShelfModel.searchText(item).indexOf(q) !== -1 })
  }
  onChosen: function(entry) { copy(entry) }
  // Esc steps back through the tile menu, then a multi-selection, and only
  // then lets the picker go back a view.
  onKeyFilter: function(event) {
    if (event.key !== Qt.Key_Escape) return
    if (shelf.menuEntry !== null) { shelf.closeMenu(); event.accepted = true }
    else if (shelf.selection.length > 0) { shelf.clearSelection(); event.accepted = true }
  }
  onActiveChanged: if (!active) { closeMenu(); clearSelection() }

  readonly property var glyphs: ({ image: "󰋩", file: "󰈔", url: "󰖟", text: "󰆒" })

  // ---------- Multi-select ----------
  //
  // Ctrl+click toggles a tile; a drag or a menu action then works on the whole
  // selection. Keys are the same identity ShelfModel dedupes by.
  property var selection: []
  property bool ripdragAvailable: false
  function isSelectedItem(item) {
    return !!item && shelf.selection.indexOf(ShelfModel.itemKey(item)) !== -1
  }
  function toggleSelected(item) {
    if (!item) return
    var key = ShelfModel.itemKey(item)
    var i = shelf.selection.indexOf(key)
    shelf.selection = i === -1
      ? shelf.selection.concat([key])
      : shelf.selection.slice(0, i).concat(shelf.selection.slice(i + 1))
  }
  function clearSelection() { shelf.selection = [] }
  // Rows a drag or menu action covers: the whole selection when the grabbed
  // tile is part of it, otherwise just that tile.
  function dragRows(row) {
    if (!row) return []
    if (shelf.selection.length > 1 && shelf.isSelectedItem(row)) {
      var out = []
      for (var i = 0; i < shelf.host.shelf.length; i++)
        if (shelf.isSelectedItem(shelf.host.shelf[i])) out.push(shelf.host.shelf[i])
      return out
    }
    return [row]
  }

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

  // Same as copy(), but for a whole selection: files go as one uri-list, text
  // as one block.
  function copyRows(rows) {
    if (!rows || !rows.length) return
    if (rows.length === 1 && rows[0].kind === "image") { copy(rows[0]); return }
    var files = [], texts = []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].kind === "file" || rows[i].kind === "image") files.push(fileUri(rows[i].path))
      else texts.push(String(rows[i].text || ""))
    }
    if (files.length)
      copier.command = ["bash", "-c", 'printf "%s" "$1" | wl-copy --type text/uri-list', "--", files.join("\r\n") + "\r\n"]
    else
      copier.command = ["bash", "-c", 'printf "%s" "$1" | wl-copy', "--", texts.join("\n")]
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

  // Fallback for apps that refuse the island's own drag: ripdrag opens a small
  // source window that does the wl_data_device dance for us.
  Process { id: ripdrag }
  Process {
    id: ripdragProbe
    command: ["bash", "-c", "command -v ripdrag"]
    running: true
    onExited: function(code) { shelf.ripdragAvailable = (code === 0) }
  }
  function dragOut(rows) {
    if (!rows || !rows.length) return
    var paths = []
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "file" || rows[i].kind === "image") paths.push(String(rows[i].path || ""))
    if (!paths.length) return
    ripdrag.command = ["ripdrag", "-x"].concat(paths)
    ripdrag.startDetached()
  }

  // A file path as a properly percent-encoded file:// URI.
  function fileUri(path) {
    var parts = String(path || "").split("/")
    for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    return "file://" + parts.join("/")
  }

  // The drag payload for a set of rows. Files and images travel as one
  // text/uri-list; plain text offers only text/* (adding a uri-list would let a
  // target paste the path instead), while a link offers both because apps
  // differ on which one they prefer.
  function mimeForRows(rows) {
    if (!rows || !rows.length) return ({})
    var files = [], texts = []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].kind === "file" || rows[i].kind === "image") files.push(fileUri(rows[i].path))
      else texts.push(String(rows[i].text || ""))
    }
    if (files.length)
      return ({ "text/uri-list": files.join("\r\n") + "\r\n" })
    var text = texts.join("\n")
    if (rows[0].kind === "url")
      return ({ "text/uri-list": text + "\r\n", "text/plain": text, "text/plain;charset=utf-8": text })
    return ({ "text/plain": text, "text/plain;charset=utf-8": text })
  }
  function mimeFor(row) { return mimeForRows(row ? [row] : []) }

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
    var many = shelf.dragRows(e).length > 1
    var actions = []
    if (e.kind === "image") {
      actions.push({ id: "copy", icon: "󰆏", label: many ? "Copy images" : "Copy image" })
      actions.push({ id: "open", icon: "󰋩", label: "Open" })
      if (shelf.ripdragAvailable) actions.push({ id: "dragout", icon: "󰇚", label: "Drag out…" })
    } else if (e.kind === "file") {
      actions.push({ id: "copy", icon: "󰆏", label: many ? "Copy files" : "Copy file" })
      actions.push({ id: "open", icon: "󰈔", label: "Open" })
      if (shelf.ripdragAvailable) actions.push({ id: "dragout", icon: "󰇚", label: "Drag out…" })
    } else if (e.kind === "url") {
      actions.push({ id: "copy", icon: "󰆏", label: "Copy link" })
      actions.push({ id: "open", icon: "󰖟", label: "Open link" })
    } else {
      actions.push({ id: "copy", icon: "󰆏", label: "Copy text" })
      actions.push({ id: "save", icon: "󰈔", label: "Save as .txt" })
    }
    actions.push({ id: "remove", icon: "󰅖", label: many ? "Remove selected" : "Remove from shelf" })
    if (shelf.host.shelf.length > 1) actions.push({ id: "clear", icon: "󰩹", label: "Clear shelf" })
    return actions
  }
  function runMenuAction(id) {
    var e = menuEntry
    var rows = shelf.dragRows(e)
    if (id === "copy") copyRows(rows)
    else if (id === "open") open(e)
    else if (id === "save") saveText(e)
    else if (id === "dragout") dragOut(rows)
    else if (id === "remove") { for (var i = 0; i < rows.length; i++) remove(rows[i]); shelf.clearSelection() }
    else if (id === "clear") { shelf.host.shelfClear(); shelf.clearSelection() }
    closeMenu()
  }

  row: Component {
    Item {
      id: tile
      property var entry: ({})
      property bool selected: false
      readonly property bool isImage: !!entry && entry.kind === "image"
      readonly property string glyph: shelf.glyphs[entry ? entry.kind : ""] || shelf.glyphs.text
      // Highlighted either as the picker's current tile or as part of the
      // Ctrl+click selection.
      readonly property bool marked: selected || shelf.isSelectedItem(entry)

      // Every tile is a card, so an empty cell reads as empty space instead of
      // a stray icon and the selected one does not look larger than the rest.
      Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 2
        radius: 10
        color: tile.marked
          ? shelf.host.withAlpha(shelf.host.colorAccent, 0.16)
          : shelf.host.withAlpha(shelf.host.colorText, 0.05)
        border.width: 1
        border.color: tile.marked
          ? shelf.host.withAlpha(shelf.host.colorAccent, 0.6)
          : shelf.host.withAlpha(shelf.host.colorText, 0.08)
        Behavior on color { ColorAnimation { duration: shelf.host.motionInstant; easing.type: shelf.host.easeStandard } }
        Behavior on border.color { ColorAnimation { duration: shelf.host.motionInstant; easing.type: shelf.host.easeStandard } }

        // Thumbnail and name, centred in the card so the compact tile still
        // looks balanced.
        Item {
          id: content
          anchors.centerIn: parent
          width: parent.width
          height: thumb.height + 4 + name.implicitHeight

          ClippingRectangle {
            id: thumb
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 34
            height: 34
            radius: 8
            color: shelf.host.withAlpha(shelf.host.colorText, 0.08)
            Image {
              id: shelfThumb
              anchors.fill: parent
              source: tile.isImage && tile.entry.path ? "file://" + tile.entry.path : ""
              sourceSize.width: 68
              sourceSize.height: 68
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
              font.pixelSize: 16
            }
          }
          Text {
            id: name
            anchors.top: thumb.bottom
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 10
            horizontalAlignment: Text.AlignHCenter
            text: String(tile.entry ? tile.entry.name || "" : "")
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            maximumLineCount: 1
            color: shelf.host.colorText
            font.family: "Adwaita Sans"
            font.pixelSize: 10
          }
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
        Drag.mimeData: shelf.mimeForRows(shelf.dragRows(tile.entry))
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
        // Ctrl+click builds a multi-selection; a plain click clears it and
        // copies the tile.
        onClicked: function(mouse) {
          if (mouse.modifiers & Qt.ControlModifier) { shelf.toggleSelected(tile.entry); return }
          shelf.clearSelection()
          shelf.copy(tile.entry)
        }
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

      // Multi-select check, opposite the remove button.
      Rectangle {
        visible: shelf.isSelectedItem(tile.entry)
        anchors.left: card.left
        anchors.top: card.top
        anchors.margins: 4
        width: 14
        height: 14
        radius: 7
        color: shelf.host.colorAccent
        Text {
          anchors.centerIn: parent
          text: "󰄬"
          color: shelf.host.colorAccentText
          font.family: shelf.host.fontFamily
          font.pixelSize: 10
        }
      }

      // Remove button, tucked inside the card's rounded corner.
      Text {
        id: removeButton
        visible: tile.selected
        anchors.right: card.right
        anchors.top: card.top
        anchors.margins: 4
        text: "󰅖"
        color: removeMouse.containsMouse ? shelf.host.colorText : shelf.host.colorMuted
        font.family: shelf.host.fontFamily
        font.pixelSize: 11
        MouseArea {
          id: removeMouse
          anchors.fill: parent
          anchors.margins: -6
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
      width: 184
      height: menuColumn.implicitHeight + 8
      x: Math.max(6, Math.min(shelf.menuX, contextMenu.width - width - 6))
      y: Math.max(6, Math.min(shelf.menuY, contextMenu.height - height - 6))
      radius: 10
      color: shelf.host.colorBackground
      border.width: 1
      border.color: shelf.host.withAlpha(shelf.host.colorText, 0.14)

      Column {
        id: menuColumn
        anchors.fill: parent
        anchors.margins: 4
        spacing: 1

        Repeater {
          model: shelf.menuActions
          delegate: Rectangle {
            required property var modelData
            width: menuColumn.width
            height: 26
            radius: 6
            color: actionMouse.containsMouse ? shelf.host.withAlpha(shelf.host.colorText, 0.1) : "transparent"
            Row {
              anchors.left: parent.left
              anchors.leftMargin: 7
              anchors.verticalCenter: parent.verticalCenter
              spacing: 7
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                horizontalAlignment: Text.AlignHCenter
                text: modelData.icon
                color: shelf.host.colorMuted
                font.family: shelf.host.fontFamily
                font.pixelSize: 13
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: shelf.host.colorText
                font.family: "Adwaita Sans"
                font.pixelSize: 12
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
