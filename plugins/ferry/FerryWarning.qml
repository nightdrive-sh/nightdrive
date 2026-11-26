import QtQuick
import qs

// Ferry's menu, under the header: why the other devices can't reach this computer, if they can't (from
// `ferry list --json`: on, tailscale, serving). It stays through a drop: hiding it would move the drop area under
// the cursor.
Rectangle {
    required property var menu
    readonly property var st: menu.st
    readonly property string why: !st ? ""
        : !st.on ? "Ferry's server isn't running. Turn it on: Launcher › System › Install › Plugins › Ferry."
        : !st.tailscale ? "Tailscale is off: your other devices can't reach this computer."
        : !st.serving ? "Not on the tailnet yet. Run once: sudo tailscale set --operator=$USER, then: ferry enable"
        : ""
    visible: why !== ""
    height: whyText.implicitHeight + 24
    radius: 12
    color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.08)
    Text {
        id: whyIcon
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: Icons.g("triangle-alert")
        color: Theme.warning
        font { family: Icons.family; pixelSize: 16 }
    }
    MenuNote {
        id: whyText
        anchors { left: whyIcon.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        variant: "warning"
        text: parent.why
    }
}
