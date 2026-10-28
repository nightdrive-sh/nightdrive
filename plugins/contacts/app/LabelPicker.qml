import QtQuick
import qs

// A line's label in the editor (mobile, home, work…): a click, or Space, Return or ↓ on it, opens the labels to pick from,
// and Custom… lets one be typed (Apple's own, "Cottage"). It edits target.label in place, as EditField does.
FocusScope {
    id: root
    required property QtObject c
    property var target: ({})
    property var options: []
    property bool open: false
    property int pick: 0
    property bool typing: false         // Custom…: the label is a field to type in
    // What it shows: target.label is a plain JS value, which tells no binding when it changes
    property string label: ""
    onTargetChanged: label = target ? target.label || "" : ""
    Component.onCompleted: label = target ? target.label || "" : ""
    implicitWidth: 96; implicitHeight: 28
    activeFocusOnTab: true
    z: open ? 10 : 0

    function show() { pick = Math.max(0, options.indexOf(label)); open = true }
    function choose(i) {
        open = false
        if (i >= options.length) { typing = true; custom.text = label; custom.forceActiveFocus(); custom.selectAll(); return }
        target.label = label = options[i]
        root.forceActiveFocus()
    }
    Keys.onPressed: e => {
        const k = e.key
        if (!open && (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Down)) show()
        else if (open && k === Qt.Key_Down) pick = Math.min(options.length, pick + 1)
        else if (open && k === Qt.Key_Up) pick = Math.max(0, pick - 1)
        else if (open && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)) choose(pick)
        else if (open && k === Qt.Key_Escape) open = false
        else return
        e.accepted = true
    }
    onActiveFocusChanged: if (!activeFocus && !custom.activeFocus) open = false

    Rectangle {
        anchors.fill: parent
        visible: !root.typing
        radius: 6
        color: hover.hovered || root.open ? root.c.hover : "transparent"
        border.color: root.activeFocus ? root.c.primary : "transparent"
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { root.forceActiveFocus(); root.open ? root.open = false : root.show() } }
        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.right: chevron.left; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.label || "label"
            color: root.label ? root.c.dim : root.c.faint; font.family: root.c.font; font.pixelSize: 12
        }
        Text {
            id: chevron
            anchors.right: parent.right; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g("chevron-down"); font.family: Icons.family; font.pixelSize: 11; color: root.c.faint
        }
    }
    // Custom…: typed in place of the button, kept when the field is left
    TextInput {
        id: custom
        visible: root.typing
        anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        color: root.c.text; font.family: root.c.font; font.pixelSize: 12
        selectionColor: root.c.sel; clip: true
        onTextEdited: root.target.label = root.label = text
        onActiveFocusChanged: if (!activeFocus) root.typing = false
        Keys.onReturnPressed: root.forceActiveFocus()
        Keys.onEscapePressed: root.forceActiveFocus()
    }

    // The labels, under the button
    Rectangle {
        visible: root.open
        y: parent.height + 4
        width: 150
        height: menu.implicitHeight + 8
        radius: 8
        color: root.c.solid
        border.color: root.c.line
        Column {
            id: menu
            x: 4; y: 4
            width: parent.width - 8
            Repeater {
                model: root.options.concat(["Custom…"])
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: menu.width; height: 26; radius: 5
                    color: index === root.pick ? root.c.sel : rowHover.hovered ? root.c.hover : "transparent"
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.choose(parent.index) }
                    Text {
                        textFormat: Text.PlainText
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData
                        color: parent.index === root.pick ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 12
                    }
                }
            }
        }
    }
}
