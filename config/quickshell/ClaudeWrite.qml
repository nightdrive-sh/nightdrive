import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Claude writes: the preview by the text after ⌘⇧C (hypr/scripts/claude-write, which reads the selection and the
// window; the place, by the text or the window: ClaudeWritePlace.qml). Claude's text shows here first, and goes in place of the selection only with Enter: Esc or a click outside
// cancels, ⌘⇧C again writes another version; the card's buttons do the same with the mouse (ClaudeWriteButton.qml).
// In a terminal it is the command for what the selection asked, with a warning when it deletes, overwrites or needs
// root; Enter puts it on the command line, it doesn't run it. In a Claude Code session (meta.claude) it is text, and
// Enter inserts it at the prompt's cursor: a terminal can't replace a selection.
// With nothing selected just now (an empty document) the card asks what to write instead, and Enter inserts it at the
// cursor: a selection stays on offer long after it's gone from the screen, so only one made in the last minute, in
// the window the key was pressed in, counts (the watcher below; the text itself isn't kept).
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
    readonly property int freshMs: 60000   // a selection older than this is an old one: the card asks instead

    property bool open: false
    property string dir: ""
    property var meta: ({})                // { addr, class, title, terminal, claude, x, y, chars }
    property string selection: ""
    property string sent: ""               // what goes to Claude, in a line: the selection, or an app's own words
    property string phase: ""              // ask | confirm | working | done | error
    property bool typed: false             // nothing was selected just now: what to write is asked, and inserted
    property real primaryAt: 0             // when the primary selection last changed, and in which window
    property string primaryAddr: ""
    property string result: ""
    property string warning: ""
    property string error: ""
    property int gen: 0                    // a draft that was cancelled or replaced answers into nothing

    function show(d) {
        dir = d
        metaFile.path = ""; metaFile.path = d + "/meta.json"
        selFile.path = ""; selFile.path = d + "/selection"
        try { meta = JSON.parse(metaFile.text()) } catch (e) { return }
        const fresh = selFile.text().trim() !== "" && Date.now() - primaryAt < freshMs && primaryAddr === addr(meta.addr)
        typed = !meta.draft && !fresh
        selection = meta.draft || typed ? "" : selFile.text()
        sent = meta.draft ? meta.sent || "" : selection
        // The screen the text is on: the caret's or the window's middle, else the focused one
        const w = meta.window, px = w ? w.x + w.w / 2 : meta.x || 0, py = w ? w.y + w.h / 2 : meta.y || 0
        const f = Hyprland.focusedMonitor
        screen = Quickshell.screens.find(s => px >= s.x && px < s.x + s.width && py >= s.y && py < s.y + s.height)
              || (f && Quickshell.screens.find(s => s.name === f.name)) || Quickshell.screens[0]
        result = ""; warning = ""; error = ""
        open = true
        keys.forceActiveFocus()
        if (typed) { request.text = ""; phase = "ask"; request.forceActiveFocus() }
        else if (meta.chars > maxChars) phase = "confirm"
        else write()
    }
    function write() {
        gen++
        phase = "working"
        keys.forceActiveFocus()
        draft.running = false
        draft.myGen = gen
        // What was typed goes to the script's folder (only you can read it) as the request, in place of the old selection
        draft.command = meta.draft
            || (typed ? ["sh", "-c", 'umask 077; printf "%s" "$1" > "$2/request" && rm -f "$2/selection" && exec "$3" draft "$2"',
                         "_", sent, dir, script]
                      : [script, "draft", dir])
        draft.running = true
    }
    function cancel() {
        if (open && meta.cancel) Quickshell.execDetached(meta.cancel)
        gen++; draft.running = false; open = false
    }
    function accept() {
        if (phase === "confirm") { write(); return }
        if (phase === "ask") {
            if (request.text.trim() === "") return
            sent = request.text.trim(); write(); return
        }
        if (phase !== "done" || result === "") return
        open = false
        // The text to the script's folder (only you can read it), then the script puts it in place, or the app that
        // asked takes it from there
        const then = meta.reply || [script, "replace", dir]
        Quickshell.execDetached(["sh", "-c", 'umask 077; printf "%s" "$1" > "$2/result" && shift 2 && exec "$@"',
                                 "_", result, dir].concat(then))
    }

    // Hyprland's addresses with or without 0x
    function addr(a) { return String(a || "").replace(/^0x/, "") }

    // Every change of the primary selection, as a line: when, and the window that had the keyboard. The text is read
    // only so the app isn't left writing into a closed pipe, and goes nowhere
    Process {
        id: primaryWatch
        property real started: 0
        command: ["wl-paste", "--primary", "--watch", "sh", "-c", "cat >/dev/null; echo"]
        running: true
        onStarted: started = Date.now()
        onExited: rewatch.start()
        stdout: SplitParser {
            onRead: {
                // wl-paste reports the selection that's already there when it starts: that one is old
                if (Date.now() - primaryWatch.started < 1000) return
                win.primaryAt = Date.now()
                win.primaryAddr = Hyprland.activeToplevel ? win.addr(Hyprland.activeToplevel.address) : ""
            }
        }
    }
    Timer { id: rewatch; interval: 5000; onTriggered: primaryWatch.running = true }

    // Another workspace, or the drawer (a special workspace) opening or closing, takes you away from the window the
    // text was for: the card closes as with Esc, instead of staying over a place it no longer belongs to
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (win.open && (e.name === "workspacev2" || e.name === "activespecial")) win.cancel()
        }
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
        function again(): void {
            if (win.open && win.phase === "ask") win.accept()
            else if (win.open && win.phase !== "confirm") win.write()
        }
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
                                                       { keys: ["Enter"], text: meta.accept || (meta.terminal ? "Put on command line" : typed || meta.claude ? "Insert" : "Replace selection"),
                                                         act: "accept", strong: true }]
        : phase === "confirm" || phase === "ask" ? [{ keys: ["Esc"], text: "Cancel", act: "cancel" }, { keys: ["Enter"], text: "Send", act: "accept", strong: true }]
        : phase === "error" ? [{ keys: ["Esc"], text: "Close", act: "cancel" }, { keys: ["Cmd", "Shift", "C"], text: "Try again", act: "write" }]
        : [{ keys: ["Esc"], text: "Cancel", act: "cancel" }]
    function act(a) {
        if (a === "cancel") cancel()
        else if (a === "accept") accept()
        else if (a === "write") write()
    }

    // By the app's caret (meta.x, meta.y: Mail's), else in the middle of the window (meta.window: the script's)
    readonly property real sx: screen ? screen.x : 0
    readonly property real sy: screen ? screen.y : 0
    ClaudeWritePlace {
        id: place
        atLine: !win.meta.window && win.meta.x !== undefined
        line: place.around((win.meta.x || 0) - win.sx, (win.meta.y || 0) - win.sy)
        window: win.meta.window ? Qt.rect(win.meta.window.x - win.sx, win.meta.window.y - win.sy, win.meta.window.w, win.meta.window.h)
                                : Qt.rect(0, 0, 0, 0)
        screenWidth: win.width; screenHeight: win.height
        width: card.width; height: card.height
    }
    // The card around the text box: its padding, header, warning and buttons. The text box gets the rest of the room
    // on its side, and scrolls what doesn't fit
    readonly property real chrome: 36 + header.height + 12 + 12 + 38 + (warn.visible ? warn.height + 12 : 0)
    readonly property real textMax: Math.max(60, place.room - chrome - 28)

    Rectangle {
        id: card
        width: Math.min(480, win.width - 32)
        height: body.implicitHeight + 36
        x: place.x
        y: place.y
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
                id: header
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
                    Text {
                        visible: win.phase === "ask"
                        width: parent.width
                        text: win.meta.terminal ? "Nothing is selected, tell Claude what the command should do"
                                                : "Nothing is selected, tell Claude what to write"
                        color: Theme.dim
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 11 }
                    }
                    // The closing quote in a Text of its own, so a long line keeps it after the "…"
                    Row {
                        visible: win.phase !== "ask"
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
                height: win.phase === "done" ? Math.min(resultText.implicitHeight, 320, win.textMax) + 28
                      : win.phase === "ask" ? Math.min(request.implicitHeight, 160, win.textMax) + 28
                      : win.phase === "working" ? 52 : note.implicitHeight + 28
                radius: 10
                color: Theme.card
                BusyDots {
                    anchors.centerIn: parent
                    visible: win.phase === "working"
                }
                // What to write, when nothing was selected: Enter sends, Shift+Enter starts a new line
                TextEdit {
                    id: request
                    visible: win.phase === "ask"
                    x: 16; y: 14
                    width: parent.width - 32; height: parent.height - 28
                    wrapMode: TextEdit.Wrap
                    clip: true
                    color: Qt.lighter(Theme.text, 1.12)
                    selectionColor: Theme.sel
                    font { family: win.meta.terminal ? "monospace" : Theme.font; pixelSize: 13 }
                    Text {
                        visible: !request.text
                        text: win.meta.terminal ? "What should the command do?" : "What should Claude write?"
                        color: Theme.dim
                        font: request.font
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) win.cancel()
                        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) win.accept()
                        else return
                        e.accepted = true
                    }
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
                id: warn
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
