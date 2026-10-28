import QtQuick
import Quickshell
import Quickshell.Io

// Theme Editor: the look's values (hypr/scripts/theme look / set) with a slider or a colour each, applied as they change.
// Opened from the launcher (Settings › Theme › Theme Editor…): qs ipc call themeeditor open.
// An ordinary window: Hyprland floats it at the right edge (hyprland.lua, float-theme-editor), ⌘⇧T tiles it like any
// other. The other windows can be clicked meanwhile, so the active and inactive borders show as they will look.
// Esc or ✕ closes. (Not named *Menu.qml: shell.qml treats those as top bar menus.)
FloatingWindow {
    id: win
    property bool open: false
    property var look: ({})      // key → value as `theme look` prints it (strings)
    readonly property string theme: Quickshell.env("HOME") + "/.config/hypr/scripts/theme"
    readonly property int labelWidth: 78      // the labels in front of the sliders and swatches

    property var colors: []      // theme colours: [{ value, name, swatch, current }] (theme list)
    property var saved: []       // themes: [{ id, name, swatch, own, state }] (theme themes)
    readonly property var inUse: saved.find(c => c.state !== "") || null
    function refresh() { lookProc.running = true; colorProc.running = true; savedProc.running = true }
    function show() { open = true; refresh() }
    // A theme's id from its name, as the script makes it
    function slug(name) { return name.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(w => w).join("-") }
    function saveAs(name) {
        Quickshell.execDetached([theme, "save", name.trim()])
        refreshSoon.restart()
    }
    property bool naming: false       // Save as…: the name field
    function use(id) {
        Quickshell.execDetached([theme, "use", id])
        refreshSoon.restart()
    }
    function setColor(c) {
        colors = colors.map(x => Object.assign({}, x, { current: x.value === c }))
        Quickshell.execDetached([theme, "color", c])
        refreshSoon.restart()
    }
    function num(key) { return parseFloat(look[key] || "0") }
    property bool resetArmed: false      // Reset asks once: a second click within a few seconds resets
    function reset() {
        if (!resetArmed) { resetArmed = true; disarm.restart(); return }
        resetArmed = false
        Quickshell.execDetached([theme, "reset"])      // the Default theme
        refreshSoon.restart()
    }
    function setValue(key, v) {
        const next = Object.assign({}, look)
        next[key] = String(v)
        look = next
        Quickshell.execDetached([theme, "set", key, String(v)])
        refreshSoon.restart()
    }

    IpcHandler {
        target: "themeeditor"
        function open(): void { win.show() }
        function toggle(): void { if (win.open) win.open = false; else win.show() }
        function close(): void { win.open = false }
    }

    Timer { id: refreshSoon; interval: 800; onTriggered: win.refresh() }
    Timer { id: disarm; interval: 4000; onTriggered: win.resetArmed = false }
    Sh {
        id: colorProc
        command: [win.theme, "list"]
        onResult: text => win.colors = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 3)
            .map(f => ({ value: f[0], name: f[1], swatch: f[2], current: f[3] === "current" }))
    }
    Sh {
        id: savedProc
        command: [win.theme, "themes"]
        onResult: text => win.saved = text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 6)
            .map(f => ({ id: f[0], name: f[1], swatch: f[2], own: f[4] === "own", state: f[5] }))
    }
    Sh {
        id: lookProc
        command: [win.theme, "look"]
        onResult: text => {
            const lk = {}
            text.split("\n").map(l => l.split("\t")).filter(f => f.length >= 2).forEach(f => lk[f[0]] = f[1])
            win.look = lk
        }
    }

    visible: open
    title: "Theme Editor"
    implicitWidth: 460
    implicitHeight: Math.min(body.implicitHeight + 44, 900)
    color: Theme.launcherBg

    // Scrolls when the window is lower than its content (tiled next to others)
    Flickable {
        id: panel
        anchors.fill: parent
        contentHeight: body.implicitHeight + 44
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        focus: true
        Keys.onEscapePressed: win.open = false
        MouseArea { anchors.fill: parent; onPressed: e => { panel.forceActiveFocus(); e.accepted = false } }

        Column {
            id: body
            x: 24; y: 20
            width: parent.width - 48
            spacing: 2

            Item {   // header: icon, name, close
                width: parent.width; height: 40
                Rectangle {
                    id: badge
                    width: 40; height: 40; radius: 20
                    color: Theme.primary
                    Text { anchors.centerIn: parent; text: Icons.g("paint-bucket"); color: Theme.bg; font { family: Icons.family; pixelSize: 20 } }
                }
                Column {
                    anchors { left: badge.right; leftMargin: 14; right: resetBtn.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Text { text: "Theme Editor"; color: Theme.accent; font { family: Theme.font; pixelSize: 18; weight: Font.DemiBold } }
                    Text {
                        text: "Changes apply as you make them"
                        color: Theme.dim; font { family: Theme.font; pixelSize: 12 }
                    }
                }
                Rectangle {   // every value back to Nightdrive's own (theme reset)
                    id: resetBtn
                    anchors { right: closeBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: resetText.implicitWidth + 24; height: 32; radius: 6
                    color: win.resetArmed ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.2)
                                          : Qt.rgba(1, 1, 1, resetArea.containsMouse ? 0.10 : 0.05)
                    Text {
                        id: resetText
                        anchors.centerIn: parent
                        text: win.resetArmed ? "Reset all?" : "Reset"
                        color: win.resetArmed ? Theme.danger : Theme.dim
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    MouseArea { id: resetArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.reset() }
                }
                Rectangle {
                    id: closeBtn
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 6
                    color: Qt.rgba(1, 1, 1, closeArea.containsMouse ? 0.10 : 0.05)   // hover: a little lighter, not the theme colour
                    Text { anchors.centerIn: parent; text: Icons.g("x"); color: Theme.dim; font { family: Icons.family; pixelSize: 16 } }
                    MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.open = false }
                }
            }
            Item { width: 1; height: 16 }

            MenuHeader { width: parent.width; title: "Theme" }
            Row {   // the theme in use (a drop-down list to load another), Save (a theme of yours, changed) and Save as…
                topPadding: 6; bottomPadding: 4
                width: parent.width
                spacing: 8
                SettingDropdown {
                    width: parent.width - saveBtn.width - saveAsBtn.width - 16
                    model: win.saved.map(c => ({ value: c.id, name: c.name, swatch: c.swatch }))
                    current: win.inUse ? win.inUse.id : undefined
                    text: win.inUse ? win.inUse.name + (win.inUse.state === "changed" ? " <font color=\"" + Theme.dim + "\">· changed</font>" : "") : "…"
                    onPicked: v => { win.naming = false; win.use(v) }
                }
                SettingButton {
                    id: saveBtn
                    text: "Save"
                    strong: true
                    // only over a theme of yours with unsaved changes; Nightdrive's own can't be replaced
                    active: !!win.inUse && win.inUse.own && win.inUse.state === "changed"
                    onClicked: win.saveAs(win.inUse.name)
                }
                SettingButton {
                    id: saveAsBtn
                    text: "Save as…"
                    onClicked: { win.naming = !win.naming; if (win.naming) nameField.forceActiveFocus() }
                }
            }
            Row {   // Save as…: the new theme's name (an existing one of yours is updated)
                id: saveRow
                visible: win.naming
                topPadding: 2; bottomPadding: 4
                width: parent.width
                spacing: 8
                readonly property var match: win.saved.find(c => c.id === win.slug(nameField.text)) || null
                readonly property bool taken: match !== null && !match.own
                readonly property bool can: win.slug(nameField.text) !== "" && !taken
                function go() { if (can) { win.saveAs(nameField.text); win.naming = false; nameField.text = "" } }
                Rectangle {
                    width: parent.width - nameSave.width - 8; height: 30; radius: 6
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.width: nameField.activeFocus ? 1 : 0
                    border.color: Theme.primary
                    TextInput {
                        id: nameField
                        anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        selectByMouse: true
                        maximumLength: 40
                        font { family: Theme.font; pixelSize: 13 }
                        onAccepted: saveRow.go()
                        Keys.onEscapePressed: win.naming = false
                        Text {
                            visible: parent.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "New theme's name"
                            color: Theme.dim
                            font: parent.font
                        }
                    }
                }
                SettingButton {
                    id: nameSave
                    text: saveRow.match && saveRow.match.own ? "Update" : "Save"
                    strong: true
                    active: saveRow.can
                    onClicked: saveRow.go()
                }
            }
            Text {
                visible: win.naming && saveRow.taken
                width: parent.width
                text: "Nightdrive's own theme has that name."
                color: Theme.warning
                font { family: Theme.font; pixelSize: 11 }
            }

            Item { width: 1; height: 14 }
            MenuHeader { width: parent.width; title: "Theme color" }
            Row {
                topPadding: 6; bottomPadding: 8
                spacing: 10
                Repeater {
                    model: win.colors
                    Rectangle {
                        required property var modelData
                        width: 22; height: 22; radius: 11
                        color: modelData.swatch
                        border.width: modelData.current ? 2 : 0
                        border.color: Theme.accent
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setColor(parent.modelData.value) }
                    }
                }
            }

            Item { width: 1; height: 14 }
            MenuHeader { width: parent.width; title: "Window background" }
            SettingColor {
                width: parent.width
                title: "Color"
                value: win.look.background || ""
                presets: [["#181722", "Nightdrive"], ["#1a1b26", "Tokyo Night"], ["#121219", "Darker"], ["#000000", "Black"]]
                onPicked: h => win.setValue("background", h)
            }
            SettingLevel {
                width: parent.width; labelWidth: win.labelWidth
                title: "Opacity"
                desc: "Terminals and the Launcher: below 100 % the wallpaper shows through"
                value: win.num("background-opacity")
                onPicked: v => win.setValue("background-opacity", v)
            }

            Item { width: 1; height: 14 }
            MenuHeader { width: parent.width; title: "Active window border" }
            SettingColor {
                width: parent.width
                title: "Color"
                value: win.look["border-color"] || ""
                presets: [["#7aa2f7", "Blue"], [String(Theme.primary), "Theme"], ["#ffffff", "White"]]
                onPicked: h => win.setValue("border-color", h)
            }
            SettingLevel {
                width: parent.width; labelWidth: win.labelWidth
                title: "Opacity"
                value: win.num("border-opacity")
                onPicked: v => win.setValue("border-opacity", v)
            }

            Item { width: 1; height: 14 }
            MenuHeader {
                width: parent.width; title: "Inactive window border"
                showToggle: true; checked: win.look["inactive-border"] !== "off"
                onToggled: win.setValue("inactive-border", checked ? "off" : "on")
            }
            Column {
                width: parent.width
                visible: win.look["inactive-border"] !== "off"
                SettingColor {
                    width: parent.width
                    title: "Color"
                    value: win.look["inactive-border-color"] || ""
                    presets: [["#595959", "Grey"], ["#454545", "Dark grey"], [String(Theme.border), "Theme"]]
                    onPicked: h => win.setValue("inactive-border-color", h)
                }
                SettingLevel {
                    width: parent.width; labelWidth: win.labelWidth
                    title: "Opacity"
                    value: win.num("inactive-border-opacity")
                    onPicked: v => win.setValue("inactive-border-opacity", v)
                }
            }

            Item { width: 1; height: 14 }
            MenuHeader {
                width: parent.width; title: "Shadow"
                showToggle: true; checked: win.look.shadow !== "off"
                onToggled: win.setValue("shadow", checked ? "off" : "on")
            }
            Column {
                width: parent.width
                visible: win.look.shadow !== "off"
                SettingLevel {
                    width: parent.width; labelWidth: win.labelWidth
                    title: "Size"
                    value: win.num("shadow-size"); to: 64; unit: "px"
                    onPicked: v => win.setValue("shadow-size", v)
                }
                SettingLevel {
                    width: parent.width; labelWidth: win.labelWidth
                    title: "Opacity"
                    value: win.num("shadow-opacity")
                    onPicked: v => win.setValue("shadow-opacity", v)
                }
                SettingColor {
                    width: parent.width
                    title: "Color"
                    value: win.look["shadow-color"] || ""
                    presets: [["#1a1a1a", "Default"], ["#000000", "Black"], [String(Theme.primary), "Theme"]]
                    onPicked: h => win.setValue("shadow-color", h)
                }
                SettingToggle {
                    width: parent.width
                    title: "Inactive windows too"
                    checked: win.look["inactive-shadow"] !== "off"
                    onPicked: v => win.setValue("inactive-shadow", v ? "on" : "off")
                }
            }

            Item { width: 1; height: 14 }
            Text {   // what doesn't follow at once (hypr/scripts/theme reload_look)
                width: parent.width
                text: "Note: Firefox, Thunderbird and Apostrophe take the window background when they start again, foot in its next window."
                wrapMode: Text.Wrap
                lineHeight: 1.15
                color: Theme.dim
                font { family: Theme.font; pixelSize: 11 }
            }
        }

    }
}
