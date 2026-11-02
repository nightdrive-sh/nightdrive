import QtQuick
import qs.kit

// Settings (⌘,): one row per choice; ←/→ or a click changes it, Esc or ⌘, closes. Apart from shell.qml, which keeps the
// settings themselves (settings.json) and shows this panel over the window.
AppPanel {
    id: settingsPanel
    required property var win
    readonly property var settingRows: [
        { key: "composeFloats", title: "New windows", choices: [[true, "Floating"], [false, "In the grid"]],
          hint: "Where writing and message windows open" },
        { key: "view", title: "Messages open as", choices: [[0, "Text"], [1, "HTML, dark"], [2, "HTML as sent"]],
          hint: "How a message shows first, when it has HTML (h changes it)" },
        { key: "claudeReads", title: "Claude reads", choices: [["thread", "The whole thread"], ["selection", "Only what I select"]],
          hint: "What is sent to Claude when it writes a reply (⌘⇧C)" }
    ]
    visible: win.showSettings
    c: win.look
    spacing: 28
    property int row: 0
    onOutsideTapped: win.showSettings = false
    Keys.onPressed: e => {
        const r = settingsPanel.settingRows[row]
        const i = r.choices.findIndex(ch => ch[0] === win.settings[r.key])
        if (e.key === Qt.Key_Escape) win.showSettings = false
        else if (e.key === Qt.Key_Down) row = Math.min(row + 1, settingsPanel.settingRows.length - 1)
        else if (e.key === Qt.Key_Up) row = Math.max(row - 1, 0)
        else if (e.key === Qt.Key_Left && i > 0) win.setting(r.key, r.choices[i - 1][0])
        else if (e.key === Qt.Key_Right && i < r.choices.length - 1) win.setting(r.key, r.choices[i + 1][0])
        else return
        e.accepted = true
    }
    Row {
        width: parent.width
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Settings"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium; width: parent.width - escHint.width }
        KeyCap { id: escHint; anchors.verticalCenter: parent.verticalCenter; c: win.look; keys: "esc" }
    }
    Repeater {
        model: settingsPanel.settingRows
        delegate: Column {
            id: settingRow
            required property var modelData
            required property int index
            width: parent.width
            spacing: 10
            Text { text: modelData.title; color: index === settingsPanel.row ? c.title : c.text; font.family: c.font; font.pixelSize: 13 }
            Row {
                spacing: 8
                Repeater {
                    model: settingRow.modelData.choices
                    delegate: Rectangle {
                        id: choice
                        required property var modelData
                        readonly property bool on: win.settings[settingRow.modelData.key] === modelData[0]
                        implicitWidth: choiceText.implicitWidth + 32
                        implicitHeight: 34
                        radius: 8
                        color: on ? c.sel : chh.hovered ? c.hover : "transparent"
                        border.color: on ? c.primary : c.line
                        HoverHandler { id: chh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { settingsPanel.row = settingRow.index; win.setting(settingRow.modelData.key, choice.modelData[0]) } }
                        Text { id: choiceText; anchors.centerIn: parent; text: choice.modelData[1]; color: choice.on ? c.title : c.dim; font.family: c.font; font.pixelSize: 12 }
                    }
                }
            }
            Text { text: settingRow.modelData.hint; color: c.faint; font.family: c.font; font.pixelSize: 11 }
        }
    }
}
