import QtQuick
import Quickshell

// The screensaver under the lock (lock.qml shows it on every lock surface after the idle time): the clock screensaver's
// face on black, over the login view. A screensaver window can't show there, as the session lock covers every window.
// Any key, click, wheel or mouse movement wakes it (woke()). The key that does is eaten here, so it never goes into
// the password; the login view is hidden meanwhile, so its field can't take keys either.
// Opaque black whatever happens: if the face fails to load, the screen stays black and the lock is untouched (a Loader,
// not the type, so an error in that file can't stop the lock from loading).
Rectangle {
    id: saver
    color: "#000000"
    signal woke()

    readonly property string faceFile: Quickshell.shellDir + "/../screensaver/clock/ClockFace.qml"
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

    // Loaded only while it shows: its timer stops, and nothing is drawn behind the login view
    Loader {
        anchors.fill: parent
        active: saver.visible
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
