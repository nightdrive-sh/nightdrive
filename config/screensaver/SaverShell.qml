// The screensaver's windows, one per screen, each showing the face of the folder it was started from: screensaver/start
// runs `qs -p screensaver/<style>`, whose shell.qml loads this file. A face is the folder's <Style>Face.qml (clock:
// ClockFace.qml), the same file the lock loads after its idle time (greeter/LockSaver.qml): a screensaver window can't
// show over the session lock. Exits on any key or mouse movement.
// The face goes in through a Loader: if it fails to load, the screen is black and any input still ends it.
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    readonly property int grace: 1000          // ms after start when input is ignored (the window opening sends a mouse event)
    // screensaver/rain → rain/RainFace.qml
    readonly property string style: Quickshell.shellDir.replace(/\/+$/, "").split("/").pop()
    readonly property string faceFile: Quickshell.shellDir + "/" + style[0].toUpperCase() + style.slice(1) + "Face.qml"

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
            WlrLayershell.namespace: "nightdrive-" + root.style
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "#000000"

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: root.quit()

                Loader { anchors.fill: parent; source: root.faceFile }

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
