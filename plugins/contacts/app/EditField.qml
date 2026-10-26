import QtQuick

// One line of the editor to type in: a quiet line under it, the placeholder in it while it's empty. It edits target[key]
// in place (the editor's draft), so the draft is always what the fields show.
FocusScope {
    id: root
    required property QtObject c
    property var target: ({})
    property string key: ""
    property string placeholder: ""
    property bool multiline: false      // the note: Return starts a new line
    property int pixelSize: 13
    readonly property alias input: loaderItem.item
    signal returnPressed()
    implicitHeight: (loaderItem.item ? loaderItem.item.implicitHeight : 18) + 14
    activeFocusOnTab: true

    // A click anywhere on the line puts the cursor in it
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onPressed: loaderItem.item.forceActiveFocus()
    }
    Loader {
        id: loaderItem
        anchors.left: parent.left; anchors.right: parent.right
        y: 6
        focus: true
        sourceComponent: root.multiline ? area : line
    }
    Component {
        id: line
        TextInput {
            focus: true
            text: root.target ? root.target[root.key] || "" : ""
            color: root.c.text; font.family: root.c.font; font.pixelSize: root.pixelSize
            selectionColor: root.c.sel; selectByMouse: true
            clip: true
            onTextEdited: root.target[root.key] = text
            Keys.onReturnPressed: root.returnPressed()
            Keys.onEnterPressed: root.returnPressed()
            Text {
                visible: !parent.text
                width: parent.width; elide: Text.ElideRight
                text: root.placeholder; color: root.c.faint; font: parent.font
            }
        }
    }
    Component {
        id: area
        TextEdit {
            focus: true
            text: root.target ? root.target[root.key] || "" : ""
            color: root.c.text; font.family: root.c.font; font.pixelSize: root.pixelSize
            selectionColor: root.c.sel; selectByMouse: true
            wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
            onTextChanged: if (activeFocus) root.target[root.key] = text
            // Tab leaves the note, as it leaves a line
            Keys.onTabPressed: e => { nextItemInFocusChain(true).forceActiveFocus(); e.accepted = true }
            Keys.onBacktabPressed: e => { nextItemInFocusChain(false).forceActiveFocus(); e.accepted = true }
            Text {
                visible: !parent.text
                width: parent.width; elide: Text.ElideRight
                text: root.placeholder; color: root.c.faint; font: parent.font
            }
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width; height: 1
        color: root.activeFocus ? root.c.primary : root.c.line
    }
}
