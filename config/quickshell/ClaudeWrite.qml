import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Claude writes: the preview next to the mouse after ⌘⇧C (hypr/scripts/claude-write, which reads the selection and the
// window). Claude's text shows here first, and goes in place of the selection only with Enter: Esc or a click outside
// cancels, ⌘⇧C again writes another version; the card's buttons do the same with the mouse (ClaudeWriteButton.qml).
// In a terminal it is the command for what the selection asked, with a warning when it deletes, overwrites or needs
// root; Enter puts it on the command line, it doesn't run it.
//   qs ipc call write open <dir>   (dir: the script's selection and meta.json)
//   qs ipc call write again
//   qs ipc call write close         as Esc (for testing: the card takes the keyboard)
//   qs ipc call write ask <dir>    another app's request (Mail's reply, plugins/mail): dir/meta.json { x, y (the
//                                  desktop's coordinates), sent (the line saying what goes to Claude), accept (Enter's
//                                  hint), draft, reply, cancel (commands, as lists) }. draft prints {text, sent} or
//                                  {error}; Enter writes dir/result and runs reply instead of pasting; cancel, if given,
//                                  runs on Esc or a click outside
// (Not named *Menu.qml: shell.qml treats those as top bar menus.)
PanelWindow {
    id: win
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/claude-write"
    readonly property int maxChars: 8000   // a longer selection is sent only after an Enter: it may be more than meant

    property bool open: false
    property string dir: ""
    property var meta: ({})                // { addr, class, title, terminal, x, y, chars }
    property string selection: ""
    property string sent: ""               // what goes to Claude, in a line: the selection, or an app's own words
    property string phase: ""              // confirm | working | done | error
    property string result: ""
    property string warning: ""
    property string error: ""
    property int gen: 0                    // a draft that was cancelled or replaced answers into nothing

    function show(d) {
        dir = d
        metaFile.path = ""; metaFile.path = d + "/meta.json"
        selFile.path = ""; selFile.path = d + "/selection"
        try { meta = JSON.parse(metaFile.text()) } catch (e) { return }
        selection = meta.draft ? "" : selFile.text()
        sent = meta.draft ? meta.sent || "" : selection
        const f = Hyprland.focusedMonitor
        screen = (f && Quickshell.screens.find(s => s.name === f.name)) || Quickshell.screens[0]
        result = ""; warning = ""; error = ""
        open = true
        keys.forceActiveFocus()
        if (meta.chars > maxChars) phase = "confirm"
        else write()
    }
    function write() {
        gen++
        phase = "working"
        draft.running = false
        draft.myGen = gen
        draft.command = meta.draft || [script, "draft", dir]
        draft.running = true
    }
    function cancel() {
        if (open && meta.cancel) Quickshell.execDetached(meta.cancel)
        gen++; draft.running = false; open = false
    }
    function accept() {
        if (phase === "confirm") { write(); return }
        if (phase !== "done" || result === "") return
        open = false
        // The text to the script's folder (only you can read it), then the script puts it in place, or the app that
        // asked takes it from there
        const then = meta.reply || [script, "replace", dir]
        Quickshell.execDetached(["sh", "-c", 'umask 077; printf "%s" "$1" > "$2/result" && shift 2 && exec "$@"',
                                 "_", result, dir].concat(then))
    }

    FileView { id: metaFile; blockLoading: true; printErrors: false }
    FileView { id: selFile; blockLoading: true; printErrors: false }
    Sh {
        id: draft
        property int myGen: 0
        onResult: text => {
            if (myGen !== win.gen || !win.open) return
            let r = {}
            try { r = JSON.parse(text) } catch (e) { r = { error: "Claude's answer didn't come through" } }
            if (r.error) { win.error = r.error; win.phase = "error"; return }
            win.result = r.text || ""; win.warning = r.warning || ""; win.phase = "done"
            if (r.sent) win.sent = r.sent
        }
    }

    IpcHandler {
        target: "write"
        function open(dir: string): void { win.show(dir) }
        function again(): void { if (win.open && win.phase !== "confirm") win.write() }
        function ask(dir: string): void { win.show(dir) }
        function close(): void { win.cancel() }
    }

    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "claude-write"

    MouseArea { anchors.fill: parent; onClicked: win.cancel() }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) win.cancel()
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.accept()
            else return
            e.accepted = true
        }
    }

    // The card's buttons: Esc's on the left, the rest on the right with Enter's last (strong). act: what a click does,
    // the same as the key
    readonly property var buttons: phase === "done" ? [{ keys: ["Esc"], text: "Cancel", act: "cancel" },
                                                       { keys: ["Cmd", "Shift", "C"], text: "Write new", act: "write" },
                                                       { keys: ["Enter"], text: meta.accept || (meta.terminal ? "Put on command line" : "Replace selection"),
                                                         act: "accept", strong: true }]
        : phase === "confirm" ? [{ keys: ["Esc"], text: "Cancel", act: "cancel" }, { keys: ["Enter"], text: "Send", act: "accept", strong: true }]
        : phase === "error" ? [{ keys: ["Esc"], text: "Close", act: "cancel" }, { keys: ["Cmd", "Shift", "C"], text: "Try again", act: "write" }]
        : [{ keys: ["Esc"], text: "Cancel", act: "cancel" }]
    function act(a) {
        if (a === "cancel") cancel()
        else if (a === "accept") accept()
        else if (a === "write") write()
    }

    // Below the mouse, kept on the screen
    readonly property real mx: (meta.x || 0) - (screen ? screen.x : 0)
    readonly property real my: (meta.y || 0) - (screen ? screen.y : 0)

    Rectangle {
        id: card
        width: Math.min(480, win.width - 32)
        height: body.implicitHeight + 36
        x: Math.max(16, Math.min(win.mx - 24, win.width - width - 16))
        y: win.my + 24 + height < win.height - 16 ? win.my + 24 : Math.max(16, win.my - 24 - height)
        radius: 14
        color: Theme.launcherBg
        border { color: Theme.primary; width: 1 }
        MouseArea { anchors.fill: parent }

        Column {
            id: body
            x: 18; y: 18
            width: parent.width - 36
            spacing: 12

            // The title, and under it what was sent in quotes, so it's clear what left the machine; the glyph is as
            // tall as the two lines
            Row {
                width: parent.width
                spacing: 10
                Text {
                    id: glyph
                    width: 36
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: Icons.g(win.meta.terminal ? "terminal" : "sparkles")
                    color: Theme.accent
                    font { family: Icons.familyThin; pixelSize: 30 }   // the thin stroke: at this size the regular one is heavy
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - glyph.width - 10
                    spacing: 2
                    Text {
                        text: win.meta.terminal ? "Claude writes the command" : "Claude writes"
                        color: Theme.title
                        font { family: Theme.font; pixelSize: 14; bold: true }
                    }
                    // The closing quote in a Text of its own, so a long line keeps it after the "…"
                    Row {
                        width: parent.width
                        Text {
                            width: Math.min(implicitWidth, parent.width - closeQuote.width)
                            text: "“" + win.sent.replace(/\s+/g, " ").trim()
                            color: Theme.dim
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 11 }
                        }
                        Text {
                            id: closeQuote
                            text: "”"
                            color: Theme.dim
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                }
            }

            // Where the text comes: there from the start, with the dots in its middle while Claude writes, and the
            // question or the error in it when there is one
            Rectangle {
                width: parent.width
                height: win.phase === "done" ? Math.min(resultText.implicitHeight, 320) + 28
                      : win.phase === "working" ? 52 : note.implicitHeight + 28
                radius: 10
                color: Theme.card
                BusyDots {
                    anchors.centerIn: parent
                    visible: win.phase === "working"
                }
                Text {
                    id: note
                    visible: win.phase === "confirm" || win.phase === "error"
                    x: 16; y: 14
                    width: parent.width - 32
                    wrapMode: Text.Wrap
                    text: win.phase === "error" ? win.error
                        : (win.meta.chars || 0).toLocaleString() + " characters are selected. Enter sends them to Claude."
                    color: win.phase === "error" ? Theme.danger : Theme.warning
                    font { family: Theme.font; pixelSize: 13 }
                }
                Flickable {
                    id: flick
                    visible: win.phase === "done"
                    x: 16; y: 14
                    width: parent.width - 32; height: parent.height - 28
                    contentHeight: resultText.implicitHeight
                    clip: true
                    Text {
                        id: resultText
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: win.result
                        textFormat: Text.PlainText
                        color: Qt.lighter(Theme.text, 1.12)
                        lineHeight: 1.15
                        font { family: win.meta.terminal ? "monospace" : Theme.font; pixelSize: 13 }
                    }
                }
                // A longer text fades out at the bottom while there is more of it to scroll to
                Rectangle {
                    visible: flick.visible && flick.contentY + flick.height < flick.contentHeight - 1
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
                    height: 36; radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Theme.card }
                    }
                }
            }
            Row {
                visible: win.phase === "done" && win.warning !== ""
                width: parent.width
                spacing: 8
                Text {
                    text: Icons.g("triangle-alert")
                    color: Theme.danger
                    font { family: Icons.family; pixelSize: 14 }
                }
                Text {
                    width: parent.width - 22
                    wrapMode: Text.Wrap
                    text: win.warning
                    color: Theme.danger
                    font { family: Theme.font; pixelSize: 13 }
                }
            }

            Item {
                width: parent.width
                height: 38
                ClaudeWriteButton {
                    readonly property var b: win.buttons[0]
                    anchors.bottom: parent.bottom
                    keys: b.keys; label: b.text
                    onClicked: win.act(b.act)
                }
                Row {
                    anchors { right: parent.right; bottom: parent.bottom }
                    spacing: 8
                    Repeater {
                        model: win.buttons.slice(1)
                        ClaudeWriteButton {
                            required property var modelData
                            keys: modelData.keys; label: modelData.text; strong: modelData.strong === true
                            onClicked: win.act(modelData.act)
                        }
                    }
                }
            }
        }
    }
}
