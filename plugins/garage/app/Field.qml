import QtQuick

// A labelled one-line text field in a frame, for the panels (a new VM's name, its ISO, a snapshot's name). Return comes
// out as accepted, Esc as escaped (the panel closes).
Column {
    id: root
    required property QtObject c
    property string label
    property string hint: ""            // after the label, smaller and grey: what goes in ("GB", "1 to 8")
    property alias text: input.text
    property alias input: input
    signal accepted()
    signal escaped()
    spacing: 6
    Row {
        spacing: 8
        Text { id: title; text: root.label; color: root.c.title; font.family: root.c.font; font.pixelSize: 13 }
        Text {
            visible: root.hint !== ""
            anchors.baseline: title.baseline
            text: root.hint; color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
        }
    }
    Rectangle {
        width: root.width; height: 32; radius: 7
        color: "transparent"
        border.color: input.activeFocus ? root.c.primary : root.c.line
        TextInput {
            id: input
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: root.c.text; font.family: root.c.font; font.pixelSize: 13
            selectionColor: root.c.sel; selectByMouse: true
            activeFocusOnTab: true
            clip: true
            onAccepted: root.accepted()
            Keys.onEscapePressed: root.escaped()
        }
    }
}
