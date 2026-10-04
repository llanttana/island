import QtQuick

// Wraps one island view (control center, a switcher, the launcher, …): names
// it, sizes the island around it, and handles showing it. The view inside
// only needs an `active` input and an implicit size.
//
// The view arrives as a Component and a Loader builds it the first time the
// surface opens. The island has twenty views and building them all at startup
// costs memory and load time for pages that may never be shown.
//
//   Surface {
//     id: emojiSurface
//     host: root; viewName: "emojis"; fixedWidth: 600
//     content: Component {
//       EmojiPicker { host: emojiSurface.host; active: emojiSurface.active }
//     }
//   }
Item {
  id: surface
  required property var host
  // The island view (and IPC route) that shows this surface.
  required property string viewName
  // Island width while open; 0 sizes it to the view's implicit width.
  property int fixedWidth: 0
  // Space between the island's edge and the view, on every side.
  property int padding: 16
  property int maxHeight: 100000
  // Whether the island takes the keyboard while this is open.
  property bool wantsKeyboard: true
  // The view itself, and whether it has been built yet.
  property Component content
  property bool built: false

  readonly property Item view: loader.item
  readonly property bool active: host.view === viewName

  readonly property real islandWidth: fixedWidth > 0 ? fixedWidth : implicitWidth + 2 * padding
  readonly property real islandHeight: Math.min(implicitHeight + 2 * padding, maxHeight)

  // Geometry comes from this surface's own size and never from the island's
  // (or the shared Views item's) animating size: opening or closing a view
  // then costs no layout at all, instead of re-laying out every view on the
  // frame the view changes.
  x: padding
  y: padding
  width: Math.max(0, islandWidth - 2 * padding)
  height: Math.max(0, islandHeight - 2 * padding)
  implicitWidth: view ? view.implicitWidth : 0
  implicitHeight: view ? view.implicitHeight : 0

  // Content fades in once the island has started morphing open.
  visible: active || opacity > 0.01
  enabled: active
  opacity: active && host.surfaceContentReady ? 1 : 0
  // Leaving is quick and arriving is unhurried, so a view change reads as one
  // page replacing another instead of two layouts showing through each other.
  Behavior on opacity {
    NumberAnimation {
      duration: (surface.active ? (surface.host.surfaceContentReady ? 190 : 110) : 80) * surface.host.motionScale
      easing.type: Easing.InOutQuad
    }
  }

  // Build on the first open, synchronously, so the size is already there when
  // the island works out how far to morph; keep it afterwards.
  onActiveChanged: if (active) built = true

  // Lets the island know this view exists (for its open/closed logic).
  Component.onCompleted: host.registerSurface(viewName)

  Loader {
    id: loader
    anchors.fill: parent
    active: surface.built
    sourceComponent: surface.content
  }
}
