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
  items: {
    var q = query.trim().toLowerCase()
    if (!q) return host.shelf
    return host.shelf.filter(function(item) { return ShelfModel.searchText(item).indexOf(q) !== -1 })
  }
  onChosen: function(entry) { copy(entry) }
  // Click copies, Alt+Enter opens a file or link, Delete takes the item off,
  // Ctrl+Delete empties the shelf.
  onKeyFilter: function(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (event.modifiers & Qt.AltModifier) { open(selected); event.accepted = true }
    } else if (event.key === Qt.Key_Delete) {
      if (event.modifiers & Qt.ControlModifier) shelf.host.shelfClear()
      else remove(selected)
      event.accepted = true
    }
  }

  readonly property var glyphs: ({ image: "󰋩", file: "󰈔", url: "󰖟", text: "󰆒" })

  // Copies the item, not just its text: an image goes back as an image, a file
  // as a file uri-list, so it can be pasted where it came from.
  Process { id: copier }
  function copy(row) {
    if (!row) return
    if (row.kind === "image")
      copier.command = ["bash", "-c", 'wl-copy --type "$1" < "$2"', "--", String(row.mime || "image/png"), String(row.path || "")]
    else if (row.kind === "file")
      copier.command = ["bash", "-c", 'p="${1// /%20}"; printf "file://%s\\n" "$p" | wl-copy --type text/uri-list', "--", String(row.path || "")]
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

  row: Component {
    Item {
      id: tile
      property var entry: ({})
      property bool selected: false
      readonly property bool isImage: !!entry && entry.kind === "image"
      readonly property string glyph: shelf.glyphs[entry ? entry.kind : ""] || shelf.glyphs.text

      ClippingRectangle {
        id: thumb
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
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
        anchors.topMargin: 6
        width: parent.width - 10
        horizontalAlignment: Text.AlignHCenter
        text: String(tile.entry ? tile.entry.name || "" : "")
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        maximumLineCount: 1
        color: shelf.host.colorText
        font.family: "Adwaita Sans"
        font.pixelSize: 11
      }
      Text {
        visible: tile.selected
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 2
        text: "󰅖"
        color: removeMouse.containsMouse ? shelf.host.colorText : shelf.host.colorMuted
        font.family: shelf.host.fontFamily
        font.pixelSize: 12
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
}
