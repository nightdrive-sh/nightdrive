import QtQuick
import Quickshell.Io
import qs
import qs.kit

// Settings (⌘,, `calendar settings`): the reminders' notifications on or off, and the reminder a timed event without one
// of its own gets. One row per choice, as Mail's: ↑ ↓ a row, ← → or a click changes it, Esc or ⌘, closes. The settings
// are the command's (`calendar reminders`, lib/settings.py), which the reminders' timer reads too: read from it on
// open and after each change, so the panel shows what the timer will do.
AppPanel {
    id: root
    required property var app
    property var settings: ({ reminders: true, default_reminder: null })
    property int row: 0
    signal closed()
    readonly property var settingRows: [
        { key: "reminders", title: "Reminders", choices: [[true, "On"], [false, "Off"]],
          hint: "An event's reminders as notifications, with Open and Snooze, also with the window closed" },
        { key: "default_reminder", title: "An event without a reminder",
          choices: [[null, "None"], [0, "At the start"], [5, "5 min"], [10, "10 min"], [15, "15 min"], [30, "30 min"], [60, "1 hour"]],
          hint: "Before an event with a time that has no reminder of its own (all-day ones get none)" }
    ]
    visible: false
    cardWidth: Math.min(520, width - 24)
    spacing: 24

    function open() { row = 0; load(); visible = true; forceActiveFocus() }
    function close() { visible = false; closed() }
    function load() { reader.running = true }
    function set(key, value) {
        if (writer.running) return
        writer.command = [app.command, "reminders", "--json"].concat(
            key === "reminders" ? [value ? "on" : "off"] : ["default", value === null ? "none" : String(value)])
        writer.running = true
    }

    Process {
        id: reader
        command: [root.app.command, "reminders", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { root.settings = JSON.parse(text).settings } catch (e) {} } }
    }
    Process {
        id: writer
        stdout: StdioCollector { onStreamFinished: { try { root.settings = JSON.parse(text).settings } catch (e) {} } }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.app.say(text.trim().split("\n").pop(), false, true) }
    }

    onOutsideTapped: close()
    Keys.onPressed: e => {
        const r = settingRows[row]
        const i = r.choices.findIndex(ch => ch[0] === settings[r.key])
        const ctrl = e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
        if (e.key === Qt.Key_Escape || (ctrl && e.key === Qt.Key_Comma)) close()
        else if (e.key === Qt.Key_Down || e.key === Qt.Key_J || e.key === Qt.Key_Tab) row = Math.min(row + 1, settingRows.length - 1)
        else if (e.key === Qt.Key_Up || e.key === Qt.Key_K || e.key === Qt.Key_Backtab) row = Math.max(row - 1, 0)
        else if ((e.key === Qt.Key_Left || e.key === Qt.Key_H) && i > 0) set(r.key, r.choices[i - 1][0])
        else if ((e.key === Qt.Key_Right || e.key === Qt.Key_L) && i < r.choices.length - 1) set(r.key, r.choices[i + 1][0])
        else return
        e.accepted = true
    }

    Row {
        width: parent.width
        Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - escHint.width
               text: "Settings"; color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium }
        KeyCap { id: escHint; anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: "esc" }
    }
    Repeater {
        model: root.settingRows
        delegate: Column {
            id: settingRow
            required property var modelData
            required property int index
            width: parent.width
            spacing: 10
            // The default means nothing while the reminders are off: dimmed, still changeable
            opacity: index === 1 && !root.settings.reminders ? 0.5 : 1
            Text { text: settingRow.modelData.title; color: settingRow.index === root.row ? root.c.title : root.c.text
                   font.family: root.c.font; font.pixelSize: 13 }
            // A Flow and a wrapping hint, so a narrow card takes the choices on more lines rather than past its edge
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: settingRow.modelData.choices
                    delegate: Rectangle {
                        id: choice
                        required property var modelData
                        readonly property bool on: root.settings[settingRow.modelData.key] === modelData[0]
                        implicitWidth: choiceText.implicitWidth + 32
                        implicitHeight: 34
                        radius: 8
                        color: on ? root.c.sel : hover.hovered ? root.c.hover : "transparent"
                        border.color: on ? root.c.primary : root.c.line
                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.row = settingRow.index; root.set(settingRow.modelData.key, choice.modelData[0]) } }
                        Text { id: choiceText; anchors.centerIn: parent; text: choice.modelData[1]
                               color: choice.on ? root.c.title : root.c.dim; font.family: root.c.font; font.pixelSize: 12 }
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.Wrap; text: settingRow.modelData.hint
                   color: root.c.faint; font.family: root.c.font; font.pixelSize: 11 }
        }
    }
}
