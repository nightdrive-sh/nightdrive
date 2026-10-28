import QtQuick

// A VM's state as the page's header says it (VmCtl.stateOf): a dot and a word, the dot in the theme's colour while it
// runs (dim while it is paused), and pulsing while it boots or shuts down, as the sidebar's does.
Row {
    id: root
    required property QtObject c
    property string vmState: "stopped"
    property bool slow: false               // a shutdown that hasn't happened yet (lib/state.sh): Force off, says why
    readonly property bool busy: vmState === "booting" || vmState === "stopping" && !slow
    spacing: 7

    Text {
        id: dot
        anchors.verticalCenter: parent.verticalCenter
        text: root.vmState === "stopped" ? "○" : "●"
        color: root.vmState === "stopped" || root.vmState === "paused" ? root.c.dim : root.c.primary
        font.family: root.c.font; font.pixelSize: 12
        SequentialAnimation on opacity {
            running: root.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.2; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutQuad }
            onRunningChanged: if (!running) dot.opacity = 1
        }
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.vmState === "booting" ? "Booting up…"
            : root.vmState === "stopping" ? (root.slow ? "Not shutting down" : "Shutting down…")
            : root.vmState === "running" ? "Running" : root.vmState === "paused" ? "Paused" : "Stopped"
        color: root.vmState === "running" ? root.c.primary : root.c.dim
        font.family: root.c.font; font.pixelSize: 12
    }
}
