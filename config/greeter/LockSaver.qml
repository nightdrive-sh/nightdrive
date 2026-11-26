import QtQuick
import Quickshell

// The screensaver under the lock (lock.qml shows it on every lock surface after the idle time): a screensaver's face
// (screensaver/<style>/<Style>Face.qml, the same file the screensaver shows) on black, over the login view. A screensaver
// window can't show there, as the session lock covers every window.
// Any key, click, wheel or mouse movement wakes it (woke()). The key that does is eaten here, so it never goes into
// the password; the login view is hidden meanwhile, so its field can't take keys either.
// Opaque black whatever happens: if the face fails to load, the screen stays black and the lock is untouched (a Loader,
// not the type, so an error in that file can't stop the lock from loading).
Rectangle {
    id: saver
    color: "#000000"
    signal woke()

    // Which face: the style setting's names (hypr/scripts/idle style), saver being the synthwave; lock.qml picks one for
    // random. "" is none yet (lock.qml hasn't read the setting); anything else is the clock.
    property string style: "clock"
    readonly property string folder: ({ saver: "synthwave", synthwave: "synthwave", rain: "rain" })[style] || "clock"
    // A file:// URL: a bare path became one of Quickshell's own qs: URLs, under which a face's other files (RainState.qml
    // beside RainFace.qml) weren't found
    readonly property string faceFile: "file://" + Quickshell.shellDir + "/../screensaver/" + folder + "/"
                                       + folder[0].toUpperCase() + folder.slice(1) + "Face.qml"
    readonly property int grace: 500    // ms after it shows when the pointer is ignored (the lock surface sends one on entry)

    property bool armed: false
    Timer { id: arm; interval: saver.grace; onTriggered: saver.armed = true }
    onVisibleChanged: {
        armed = false; mouse.last = Qt.point(-1, -1)
        if (visible) { arm.restart(); forceActiveFocus() }
    }
    Component.onCompleted: if (visible) { arm.restart(); forceActiveFocus() }
    // A lock that starts with the saver: the surface's window becomes active only after this was made, and then Qt gave
    // the keyboard to the hidden password field (focus: true), not here. So the keyboard is taken again then.
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: if (windowActive && visible) forceActiveFocus()

    // Keys wake it at once, also in the grace time: a key is never sent by the surface itself
    Keys.onPressed: event => { event.accepted = true; saver.woke() }
    Keys.onReleased: event => { event.accepted = true }

    // Loaded only while it shows: its timer stops, and nothing is drawn behind the login view (and a style picked for
    // the next time loads then)
    Loader {
        anchors.fill: parent
        active: saver.visible && saver.style !== ""
        source: saver.faceFile
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        property point last: Qt.point(-1, -1)
        // The first report only says where the pointer is; a nudge of a pixel or two (a desk knocked) doesn't count
        onPositionChanged: m => {
            if (saver.armed && last.x >= 0 && (Math.abs(m.x - last.x) > 2 || Math.abs(m.y - last.y) > 2)) saver.woke()
            last = Qt.point(m.x, m.y)
        }
        onPressed: saver.woke()
        onWheel: saver.woke()
    }
}
