import QtQuick
import qs

// One machine in Tailscale's menu: a click opens ssh to it (sshAllowed and an online computer), else copies its IP; the
// copy button at the right edge always copies.
MenuRow {
    id: peer
    required property var menu          // TailscaleMenu: ssh(), copy(), sshable(), copied
    required property var modelData     // { host, ip, online, os, owner }
    property bool sshAllowed: true      // another user's machine copies on a click: ssh there isn't ours to offer
    readonly property bool canSsh: sshAllowed && menu.sshable(modelData)

    icon: /mac|ios/i.test(modelData.os) ? "laptop" : /android/i.test(modelData.os) ? "smartphone" : "server"
    label: modelData.host
    active: false
    detail: menu.copied === modelData.ip ? "copied" : modelData.ip
    opacity: modelData.online ? 1 : 0.5
    // The copy icon takes the check's place at the right edge, so the IP stays beside it; smaller than a row's icon
    checkIcon: menu.copied === modelData.ip ? "check" : "copy"
    checkIconSize: 13
    onClicked: canSsh ? menu.ssh(modelData.host) : menu.copy(modelData.ip)

    // The copy button over the icon: its own faint background under the mouse, above the row's own MouseArea (z), so a
    // click there copies instead of opening ssh
    Rectangle {
        z: -1   // under the icon, over the row's background
        anchors { right: parent.right; rightMargin: peer.pad - 6; verticalCenter: parent.verticalCenter }
        width: 25; height: 24; radius: 5
        color: copyArea.containsMouse && !MenuPointer.pointerAway ? Theme.sel : "transparent"
    }
    MouseArea {
        id: copyArea
        z: 1
        anchors { right: parent.right; rightMargin: peer.pad - 6; verticalCenter: parent.verticalCenter }
        width: 25; height: 24
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: peer.menu.copy(peer.modelData.ip)
    }
}
