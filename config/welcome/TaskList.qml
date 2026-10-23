import QtQuick
import qs
import qs.kit

// Welcome's list: what is still to set up, one row each (TaskRow). Enter sets the picked one up, with Claude or by hand
// as the first question was answered (shell.qml's activate); c changes that answer, s puts a row aside.
Item {
    id: root
    required property var app
    required property QtObject c
    readonly property var task: app.rows[app.current] || {}

    function key(e) {
        const k = e.key
        if (k === Qt.Key_Down || k === Qt.Key_J) app.current = Math.min(app.current + 1, app.rows.length - 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) app.current = Math.max(app.current - 1, 0)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) app.activate(app.current)
        else if (k === Qt.Key_S) app.skip(app.current)
        else if (k === Qt.Key_C) app.choose(app.manual ? "claude" : "manual")
        else if (k === Qt.Key_Escape) app.close()
        else return false
        return true
    }

    Column {
        id: head
        x: 40; y: 40
        width: parent.width - 80
        spacing: 16
        AppTitle { c: root.c; text: "Welcome to Nightdrive"; pixelSize: 24 }
        Text {
            width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.25
            color: root.c.text; font.family: root.c.font; font.pixelSize: 13
            text: root.app.manual
                ? "Set these up here, one step at a time: pick one and press Enter for its steps. Skip what you don't "
                  + "need. You can come back any time from the launcher › System › Set up Nightdrive."
                : "Sign in to Claude first. Then pick one and press Enter: Claude sets it up with you in a terminal and "
                  + "explains as it goes. Skip what you don't need. You can come back any time from the launcher › "
                  + "System › Set up Nightdrive."
        }
    }

    ListView {
        id: list
        x: 26; y: head.y + head.height + 24
        width: parent.width - 52
        height: foot.y - y - 16
        clip: true
        spacing: 2
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: root.app.rows
        currentIndex: root.app.current
        highlightMoveDuration: 0
        delegate: TaskRow {
            required property var modelData
            c: root.c
            task: modelData
            selected: index === root.app.current
            claudeIn: root.app.claudeIn
            manual: root.app.manual
            onActivated: root.app.activate(index)
        }
    }

    // The keys, for the mouse too
    Item {
        id: foot
        x: 40; y: parent.height - height - 28
        width: parent.width - 80
        height: 40
        Row {
            spacing: 12
            anchors.verticalCenter: parent.verticalCenter
            KeyCap { c: root.c; keys: "↑  ↓"; tint: root.c.faint; anchors.verticalCenter: parent.verticalCenter }
            FootButton {
                c: root.c
                visible: !root.task.done && !root.task.running
                keys: "s"; label: root.task.mark === "skipped" ? "Don't skip" : "Skip this"
                onClicked: root.app.skip(root.app.current)
            }
            FootButton {
                c: root.c
                keys: "c"; label: root.app.manual ? "I have Claude now" : "Set up by hand"
                onClicked: root.app.choose(root.app.manual ? "claude" : "manual")
            }
        }
        FootButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            c: root.c
            keys: "esc"; label: root.app.finished ? "Finish" : "Skip for now"
            strong: root.app.finished
            onClicked: root.app.close()
        }
    }
}
