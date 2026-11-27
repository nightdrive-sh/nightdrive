import QtQuick
import qs.kit

// Settings' list of the account's sorting rules (#3733): each sender (or domain) and the folder its mail goes to, with
// ✕ (or ⌫ on the row the keys are on) ending it; ⌘Z brings it back. The rules come from dragging mail into your own
// folders, so there is nothing to add here. Apart from SettingsPanel.qml, which places it under the settings and moves
// the keys into it (current).
Column {
    id: root
    required property var win
    property int current: -1            // the row the keys are on, or -1
    readonly property var rules: win.sorter.rules.filter(r => r.account === win.account.id)
        .slice().sort((a, b) => (a.folder + (a.sender || a.domain)).localeCompare(b.folder + (b.sender || b.domain)))
    readonly property QtObject c: win.look
    spacing: 10
    function removeAt(i) { if (rules[i]) win.operations.stopSorting(rules[i]) }

    Text { text: "Sorting"; color: root.current >= 0 ? c.title : c.text; font.family: c.font; font.pixelSize: 13 }
    Text {
        width: parent.width; wrapMode: Text.Wrap; color: c.faint; font.family: c.font; font.pixelSize: 11
        text: root.rules.length ? "Mail from these goes to its folder as it arrives, without a notification (" + win.account.address + ")"
                                : "Drag a message into a folder of your own, and its sender's mail goes there from then on"
    }
    Repeater {
        model: root.rules
        delegate: Rectangle {
            id: ruleRow
            required property var modelData
            required property int index
            width: root.width
            implicitHeight: 32
            radius: 8
            color: index === root.current ? c.sel : rh.hovered ? c.hover : "transparent"
            HoverHandler { id: rh }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60; elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: (ruleRow.modelData.sender || "all of " + ruleRow.modelData.domain) + "  →  " + ruleRow.modelData.folder
                color: c.text; font.family: c.font; font.pixelSize: 12
            }
            AppIconButton {
                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                visible: rh.hovered || ruleRow.index === root.current
                c: root.c
                glyph: "x"
                tip: "Stop sorting"; keys: "⌫"; tipAlign: "right"
                onClicked: root.removeAt(ruleRow.index)
            }
        }
    }
}
