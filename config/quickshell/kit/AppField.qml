import QtQuick

// A labelled one-line text field in a frame, for the panels (Garage: a new VM's name, its ISO, a snapshot's name).
// Return comes out as accepted, Esc as escaped (the panel closes). Typing into one that is read-only comes out as
// refused, so the panel can say why rather than the keys doing nothing. A part built on it (AppDatePicker) sees each key
// first through keyFilter, a function(event) that accepts what it takes, and keeps endRoom free at the frame's right.
Column {
    id: root
    required property QtObject c
    property string label
    property string hint: ""            // after the label, smaller and grey: what goes in ("GB", "1 to 8")
    property alias text: input.text
    property alias input: input
    property var keyFilter: null        // function(e): sees each key before the field; e.accepted = true takes it
    property int endRoom: 0             // room at the frame's right for a part's own glyph
    readonly property Item frame: box   // the framed box, under the label: where a popup hangs from
    signal accepted()
    signal escaped()
    signal refused()
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
        id: box
        width: root.width; height: 32; radius: 7
        color: "transparent"
        border.color: input.activeFocus ? root.c.primary : root.c.line
        TextInput {
            id: input
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10 + root.endRoom
            verticalAlignment: TextInput.AlignVCenter
            color: root.c.text; font.family: root.c.font; font.pixelSize: 13
            selectionColor: root.c.sel; selectByMouse: true
            activeFocusOnTab: true
            clip: true
            onAccepted: root.accepted()
            // Esc here rather than in Keys.onEscapePressed, which Qt calls before onPressed: the filter would never see it
            Keys.onPressed: e => {
                if (root.keyFilter) { e.accepted = false; root.keyFilter(e); if (e.accepted) return }
                if (e.key === Qt.Key_Escape) { root.escaped(); e.accepted = true; return }
                if (readOnly && (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete || (e.text.length && e.text.charCodeAt(0) >= 32)))
                    root.refused()
                e.accepted = false
            }
        }
    }
}
