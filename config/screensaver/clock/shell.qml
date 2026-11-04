// Nightdrive screensaver 3: a big clock on black (ClockFace.qml), on every screen. Run by screensaver/start as its own
// Quickshell instance (qs -p this folder). Exits on any key or mouse movement. Under the lock the lock shows the same
// face itself (greeter/LockSaver.qml): this window can't show over it.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property int grace: 1000          // ms after start when input is ignored (the window opening sends a mouse event)

    property bool armed: false
    Timer { interval: root.grace; running: true; onTriggered: root.armed = true }

    function quit() { if (armed) Qt.quit() }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "nightdrive-clock"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "#000000"

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: root.quit()

                ClockFace { anchors.fill: parent }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    property point last: Qt.point(-1, -1)
                    // the first report only says where the pointer is (also when a notification over it goes away)
                    onPositionChanged: m => {
                        if (last.x >= 0 && (Math.abs(m.x - last.x) > 2 || Math.abs(m.y - last.y) > 2)) root.quit()
                        last = Qt.point(m.x, m.y)
                    }
                    onPressed: root.quit()
                    onWheel: root.quit()
                }
            }
        }
    }
}
