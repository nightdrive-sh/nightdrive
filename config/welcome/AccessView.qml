import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Welcome's step "Claude's access" (tasks: only with Claude Code installed): how much Claude may use of the desktop
// through Nightdrive's MCP server (config/mcp). A level writes ~/.config/nightdrive/claude-access.json (`nightdrive mcp
// access level …`, access.py owns the file) and turns the server on in Claude Code (`nightdrive mcp install --yes`:
// choosing here is the yes). Off, picked to begin with (Dashboard #1837: turning Claude on is the user's own step), leaves
// it off and the row skipped. Settings › Claude › Access changes it later, area by area. Esc goes back to the list.
Item {
    id: root
    required property var app
    required property QtObject c
    property int current: 3
    property string error: ""
    readonly property string nd: app.dir + "/../../bin/nightdrive"   // this checkout's, as the window is
    signal done()

    readonly property var choices: [
        { level: "strict", icon: "shield", name: "Strict",
          about: "Only Nightdrive's docs and status: Claude tells you how things work, and where to find them." },
        { level: "normal", icon: "shield-half", name: "Normal", tag: "(recommended)",
          about: "Claude reads and changes your apps and settings, each change with Undo. Reading your mail, contacts, "
               + "calendar, notes, notifications or screen asks you each time, and so does deleting." },
        { level: "open", icon: "shield-check", name: "Open",
          about: "Claude also reads all of it, and deletes to the trash, without asking. Sending, devices and "
               + "installing still ask." },
        { level: "", icon: "circle-slash", name: "Off",
          about: "Claude Code doesn't get Nightdrive's tools: Settings › Claude › Access turns them on later." }
    ]

    // When shown, the level chosen before is picked; Off until there is one
    onVisibleChanged: if (visible) { error = ""; reader.running = true }
    Process {
        id: reader
        command: [root.nd, "mcp", "access"]
        stdout: StdioCollector {
            onStreamFinished: {
                let now = {}
                try { now = JSON.parse(text) } catch (e) {}
                const i = now.chosen ? root.choices.findIndex(ch => ch.level === now.level) : -1
                root.current = i < 0 ? root.choices.length - 1 : i
            }
        }
    }
    // The level and the server in one go; a failure stays on screen in its own words
    Process {
        id: worker
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (code === 0) { root.app.refresh(); root.done(); return }
            root.error = (err.text.trim() || out.text.trim()).split("\n").pop() || "It didn't work (exit " + code + ")"
        }
    }

    function choose(i) {
        const ch = choices[i]
        current = i
        if (worker.running) return
        error = ""
        if (ch.level === "") {
            app.run([app.setupCmd, "mark", "claude-access", "skipped"])
            done()
            return
        }
        worker.command = ["bash", "-c", '"$1" mcp access level "$2" && "$1" mcp install --yes', "_", nd, ch.level]
        worker.running = true
    }

    function key(e) {
        const k = e.key, enter = k === Qt.Key_Return || k === Qt.Key_Enter
        if (e.modifiers & Qt.ControlModifier) return false
        else if (k === Qt.Key_Down || k === Qt.Key_J) current = Math.min(current + 1, choices.length - 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) current = Math.max(current - 1, 0)
        else if (enter) choose(current)
        else if (k >= Qt.Key_1 && k < Qt.Key_1 + choices.length) choose(k - Qt.Key_1)
        else if (k === Qt.Key_Escape || k === Qt.Key_Left || k === Qt.Key_Backspace) done()
        else return false
        return true
    }

    Column {
        id: head
        x: 40; y: 32
        width: parent.width - 80
        spacing: 10
        Row {
            spacing: 12
            AppTitle { id: title; c: root.c; text: "Claude's access"; pixelSize: 24 }
            Text {
                anchors.verticalCenter: title.verticalCenter; anchors.verticalCenterOffset: 2
                text: "Experimental"
                color: root.c.primary; font.family: root.c.font; font.pixelSize: 13
            }
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.25
            color: root.c.text; font.family: root.c.font; font.pixelSize: 13
            text: "In any Claude Code session, Claude can use your desktop for you: find a mail, change the wallpaper, "
                + "tell you how Nightdrive works. How much may it do?"
        }
        // What leaves the computer, said before the level is chosen (Dashboard #1834): plainly, without alarm
        Text {
            width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.25
            color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
            text: "When Claude reads your mail, contacts, calendars, notes, files or windows with a tool, they go to "
                + "Claude's service (Anthropic) in the conversation. Limit it here or in Settings › Claude › Access; use it "
                + "at your own risk."
        }
    }

    Column {
        id: rows
        x: 26; y: head.y + head.height + 12
        width: parent.width - 52
        spacing: 2
        Repeater {
            model: root.choices
            delegate: AppRow {
                id: row
                required property var modelData
                required property int index
                width: rows.width
                c: root.c
                selected: index === root.current
                height: about.y + about.height + 12
                TapHandler { onTapped: root.choose(row.index) }
                Text {
                    x: 14; y: 13
                    text: Icons.g(row.modelData.icon); font.family: Icons.family; font.pixelSize: 16
                    color: row.selected ? root.c.accent : root.c.dim
                }
                Row {
                    id: name
                    x: 44; y: 12
                    spacing: 6
                    Text {
                        text: row.modelData.name
                        color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        visible: text !== ""
                        text: row.modelData.tag || ""
                        color: root.c.primary; font.family: root.c.font; font.pixelSize: 13
                    }
                }
                Text {
                    id: about
                    x: 44; y: name.y + name.height + 3
                    width: row.width - x - 130
                    text: row.modelData.about; wrapMode: Text.Wrap; lineHeight: 1.15
                    color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
                }
                Row {
                    visible: row.selected
                    x: row.width - width - 14; y: 13
                    spacing: 8
                    BusyDots { visible: worker.running; anchors.verticalCenter: parent.verticalCenter }
                    AppKeyAction {
                        visible: !worker.running
                        c: root.c
                        keys: "⏎"; label: "Choose"
                        color: root.c.primary; hoverColor: root.c.title
                        onClicked: root.choose(row.index)
                    }
                }
            }
        }
    }

    // What the levels don't change: the card for what has consequences, and the way to change it later
    Text {
        x: 40; y: rows.y + rows.height + 12
        width: parent.width - 80
        wrapMode: Text.Wrap; lineHeight: 1.25
        color: root.error ? root.c.danger : root.c.dim; font.family: root.c.font; font.pixelSize: 12
        text: root.error || "Claude never sees your passwords, and nothing sends or installs without your Enter on "
            + "Nightdrive's card."
    }

    Item {
        x: 40; y: parent.height - height - 28
        width: parent.width - 80
        height: 40
        FootButton {
            anchors.verticalCenter: parent.verticalCenter
            c: root.c
            keys: "esc"; label: "Back"
            onClicked: root.done()
        }
    }
}
