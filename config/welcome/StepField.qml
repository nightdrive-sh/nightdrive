import QtQuick
import qs

// A field a step of StepView asks for (steps.md's Ask:): its label, and a line to type in, with the example greyed
// while it's empty. Keys stay in it while it has them: Enter or Tab goes on to the next field, Shift+Tab to the one
// before (from the first, back to the step), Esc back to the step.
Column {
    id: root
    required property QtObject c
    property string label
    property string placeholder
    property string value
    readonly property alias input: input
    signal edited(string text)
    signal done()
    signal previous()
    signal leave()
    spacing: 6

    Text { text: root.label; color: root.c.dim; font.family: root.c.font; font.pixelSize: 12 }
    Rectangle {
        width: root.width; height: 32; radius: 7
        color: "transparent"
        border.color: input.activeFocus ? root.c.primary : root.c.line
        TextInput {
            id: input
            x: 12; width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            clip: true
            color: root.c.title; selectionColor: root.c.sel; selectedTextColor: root.c.title
            font.family: root.c.font; font.pixelSize: 13
            onTextEdited: root.edited(text)
            onAccepted: root.done()
            // What the field doesn't use (Esc, Tab, an arrow at its end) stays here, not the step's keys
            Keys.priority: Keys.AfterItem
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Tab) root.done()
                else if (e.key === Qt.Key_Backtab) root.previous()
                else if (e.key === Qt.Key_Escape) root.leave()
                e.accepted = true
            }
        }
        Text {
            visible: input.text === ""
            x: input.x; anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder; color: root.c.faint; font.family: root.c.font; font.pixelSize: 13
        }
        TapHandler { onTapped: input.forceActiveFocus() }
    }
}
