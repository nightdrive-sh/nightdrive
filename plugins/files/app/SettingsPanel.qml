import QtQuick
import qs.kit

// Files' settings (⌘,, the sidebar title's gear, `files settings`): one row per choice, as Mail's; ←/→ or a click
// changes it, ↑/↓ go between rows, Esc or ⌘, closes. shell.qml keeps the settings themselves (settings.json), shared by
// every window, so a change shows in all of them at once.
AppPanel {
    id: panel
    required property var win             // FilesWindow: settings, setting(), showSettings, look
    readonly property var settingRows: [
        { key: "layout", title: "Layout", choices: [["normal", "Normal"], ["compact", "Compact"]],
          hint: "Normal rows are taller and easier to click; compact ones fit more files in the window" }
    ]
    visible: win.showSettings
    c: win.look
    cardWidth: Math.min(480, parent ? parent.width - 32 : 480)
    spacing: 28
    property int row: 0
    onVisibleChanged: if (visible) forceActiveFocus()
    onOutsideTapped: win.showSettings = false
    Keys.onPressed: e => {
        const r = settingRows[row]
        const i = r.choices.findIndex(ch => ch[0] === win.settings[r.key])
        const cmd = (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0
        if (e.key === Qt.Key_Escape || (e.key === Qt.Key_Comma && cmd)) win.showSettings = false
        else if (e.key === Qt.Key_Down) row = Math.min(row + 1, settingRows.length - 1)
        else if (e.key === Qt.Key_Up) row = Math.max(row - 1, 0)
        else if (e.key === Qt.Key_Left && i > 0) win.setting(r.key, r.choices[i - 1][0])
        else if (e.key === Qt.Key_Right && i < r.choices.length - 1) win.setting(r.key, r.choices[i + 1][0])
        else return
        e.accepted = true
    }
    Row {
        width: parent.width
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Settings"; color: panel.c.title; font.family: panel.c.font; font.pixelSize: 15; font.weight: Font.Medium; width: parent.width - escHint.width }
        KeyCap { id: escHint; anchors.verticalCenter: parent.verticalCenter; c: panel.c; keys: "esc" }
    }
    Repeater {
        model: panel.settingRows
        delegate: Column {
            id: settingRow
            required property var modelData
            required property int index
            width: parent.width
            spacing: 10
            Text { text: modelData.title; color: index === panel.row ? panel.c.title : panel.c.text; font.family: panel.c.font; font.pixelSize: 13 }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: settingRow.modelData.choices
                    delegate: Rectangle {
                        id: choice
                        required property var modelData
                        readonly property bool on: panel.win.settings[settingRow.modelData.key] === modelData[0]
                        implicitWidth: choiceText.implicitWidth + 32
                        implicitHeight: 34
                        radius: 8
                        color: on ? panel.c.sel : chh.hovered ? panel.c.hover : "transparent"
                        border.color: on ? panel.c.primary : panel.c.line
                        HoverHandler { id: chh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { panel.row = settingRow.index; panel.win.setting(settingRow.modelData.key, choice.modelData[0]) } }
                        Text { id: choiceText; anchors.centerIn: parent; text: choice.modelData[1]; color: choice.on ? panel.c.title : panel.c.dim; font.family: panel.c.font; font.pixelSize: 12 }
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.Wrap; text: settingRow.modelData.hint; color: panel.c.faint; font.family: panel.c.font; font.pixelSize: 11 }
        }
    }
}
