import QtQuick
import qs

// A form's text field on a launcher row (a level file's row with `field: true`): the box at the row's right end. While the
// row is selected, what is typed goes here instead of the search line (Launcher.qml's fieldRow), with a caret; otherwise
// the row's value (`summary`), or its `placeholder` dimmed. `unit` follows a typed value (" px"). Enter on the row is the
// level file's activate(), which reads launcher.query and calls launcher.clearQuery() once it has taken it.
Rectangle {
    id: f
    property var row: ({})                    // the row's model data
    property bool current: false              // selected: typing goes here
    property string typed: ""                 // the launcher's query, while current
    property int fontSize: 14

    readonly property bool editing: current && typed !== ""
    readonly property string value: row.summary !== undefined && row.summary !== "" ? String(row.summary) : ""
    width: Math.max(180, label.implicitWidth + 32)
    radius: 8
    // Quiet: a faint well in the row, its edge a little brighter while typed into, not a black box with a bright frame
    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
    border { width: 1; color: current ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10) }

    Text {
        id: label
        anchors { right: caret.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
        text: f.editing ? f.typed + (f.row.unit || "") : f.value !== "" ? f.value : (f.row.placeholder || "")
        color: f.editing || f.value !== "" ? Theme.text : Theme.dim
        font { family: Theme.font; pixelSize: f.fontSize }
    }
    // The caret at the end: the value is typed at its end, as the search line's
    Rectangle {
        id: caret
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: 2; height: f.fontSize + 4
        color: Theme.primary
        visible: f.current && blink.on
        Timer { id: blink; property bool on: true; interval: 530; repeat: true; running: f.current; onTriggered: on = !on; onRunningChanged: on = true }
    }
}
