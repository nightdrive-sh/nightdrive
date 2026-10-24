import QtQuick
import qs
import qs.kit

// Welcome's list: what is still to set up, one row each (TaskRow). Enter sets the picked one up, with Claude, by hand
// or from its README, as the first question was answered (shell.qml's activate); Back asks that question again. A row
// you don't want is just left: Skip for now puts aside what isn't done.
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
        else if (k === Qt.Key_Left || k === Qt.Key_Backspace) app.choose("")
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
            text: root.app.selfPath
                ? "Each app's README tells how to set it up: pick one to open it, and set it up your own way. Press "
                  + "Finish when you're done. You can come back any time from the Launcher › System › Set up Nightdrive."
                : root.app.manual ? "Set up each app below. You'll get step-by-step instructions for each app."
                : "Sign in to Claude first. Then proceed to the next apps."
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
            selfPath: root.app.selfPath
            onActivated: root.app.activate(index)
        }
    }

    // Back to the first question on the left, for a choice made by mistake; the way out on the right
    Item {
        id: foot
        x: 40; y: parent.height - height - 28
        width: parent.width - 80
        height: 40
        FootButton {
            anchors.verticalCenter: parent.verticalCenter
            c: root.c
            keys: "←"; label: "Back"
            onClicked: root.app.choose("")
        }
        FootButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            c: root.c
            keys: "esc"; label: root.app.finished || root.app.selfPath ? "Finish" : "Skip for now"
            strong: root.app.finished
            onClicked: root.app.close()
        }
    }
}
