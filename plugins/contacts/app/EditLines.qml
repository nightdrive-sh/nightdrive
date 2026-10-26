import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// A kind of line in the editor (the numbers, the email addresses, the addresses, the links): each with its label, its
// value and a button to take it away, and one to add another. draft[key] is the list it edits; a line keeps the ref and
// orig it was loaded with (cards.py), which edit.py writes it back by.
ColumnLayout {
    id: root
    required property QtObject c
    property var draft: ({})
    property string key: ""
    property var options: []
    property string placeholder: ""
    property string addText: ""
    property bool address: false
    property var lines: []
    property bool focusNew: false
    property int menus: 0               // label menus open: they draw over the sections below, so this one rises
    z: menus > 0 ? 10 : 0
    spacing: 6

    function reload() { lines = draft && draft[key] ? draft[key] : [] }
    onDraftChanged: reload()
    Component.onCompleted: reload()

    function blank() {
        const x = { label: options[0], ref: -1, orig: null }
        if (address) for (const f of ["street", "code", "city", "region", "country"]) x[f] = ""
        else x.value = ""
        return x
    }
    function add() { focusNew = true; draft[key] = lines = lines.concat([blank()]) }
    function remove(i) { const l = lines.slice(); l.splice(i, 1); draft[key] = lines = l }

    // By index: a Repeater's modelData is a copy of the line, and the fields must edit the draft's own
    Repeater {
        model: root.lines.length
        delegate: RowLayout {
            id: row
            required property int index
            readonly property var line: root.lines[index]
            Layout.fillWidth: true
            spacing: 10
            z: picker.open ? 10 : 0
            Component.onCompleted: if (root.focusNew && index === root.lines.length - 1) { root.focusNew = false; (root.address ? street : first).forceActiveFocus() }
            LabelPicker {
                id: picker
                Layout.alignment: Qt.AlignTop
                onOpenChanged: root.menus += open ? 1 : -1
                Layout.preferredWidth: 104
                c: root.c
                target: row.line
                options: root.options
            }
            // A number, an address, a link: one line
            EditField {
                id: first
                visible: !root.address
                Layout.fillWidth: true
                c: root.c
                target: row.line; key: "value"
                placeholder: root.placeholder
            }
            // An address: the street, the postal code and town, the region and country
            ColumnLayout {
                visible: root.address
                Layout.fillWidth: true
                spacing: 4
                EditField {
                    id: street
                    Layout.fillWidth: true
                    c: root.c; target: row.line; key: "street"; placeholder: "Street"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    EditField { Layout.preferredWidth: 90; c: root.c; target: row.line; key: "code"; placeholder: "Postal code" }
                    EditField { Layout.fillWidth: true; c: root.c; target: row.line; key: "city"; placeholder: "City" }
                }
                EditField { Layout.fillWidth: true; c: root.c; target: row.line; key: "region"; placeholder: "Region" }
                EditField { Layout.fillWidth: true; c: root.c; target: row.line; key: "country"; placeholder: "Country" }
            }
            AppIconButton {
                Layout.alignment: Qt.AlignTop
                c: root.c
                glyph: "x"; glyphColor: c.faint; hoverColor: c.sel
                tip: "Take it away"
                onClicked: root.remove(row.index)
            }
        }
    }
    // Add another: a quiet line, which Tab reaches and Return or Space presses
    Rectangle {
        id: addButton
        Layout.preferredWidth: addRow.implicitWidth + 16
        Layout.preferredHeight: 28
        radius: 6
        activeFocusOnTab: true
        color: addHover.hovered ? c.hover : "transparent"
        border.color: activeFocus ? c.primary : "transparent"
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.add(); e.accepted = true }
        }
        HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.add() }
        Row {
            id: addRow
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text { text: Icons.g("plus"); font.family: Icons.family; font.pixelSize: 12; color: root.c.primary; anchors.verticalCenter: parent.verticalCenter }
            Text { text: root.addText; color: root.c.dim; font.family: root.c.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
