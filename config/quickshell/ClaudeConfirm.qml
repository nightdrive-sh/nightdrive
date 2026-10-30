import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Claude's confirmation card: an action with consequences (sending a mail, a device, installing) that Claude asked
// Nightdrive's MCP server to do waits here for the user (config/mcp/confirm.py, Dashboard #1766), and so does any call
// whose right the user set to Ask in Access (#1831): a read, a change, a delete, each with its own heading and a line
// on what follows from allowing it. It shows the tool and every argument as plain text; Enter or Allow runs it, Esc or
// Deny refuses, and so does the countdown running out. A card longer than the screen allows only once it has been
// scrolled to the end (#1837): a mail's last lines or a package list's tail mustn't go unseen.
// confirm.py treats anything but an allow as a refusal: a card that never opened, closed or reloaded without an answer.
//   qs ipc call claudeConfirm open <file>   shows the request (confirm.py's JSON): "shown <md5 of what was read>", or
//                                           "busy" while another card is up (confirm.py tries again)
//   qs ipc call claudeConfirm answer <id>   allow | deny | timeout (once, then forgotten), pending, or gone
//   qs ipc call claudeConfirm close <id>    refuses it (confirm.py gave up)
// There is deliberately no IPC call that allows: only a key or a click on the card does.
// The card doesn't take the keyboard from someone typing: it waits for a second without input (or a click on it), and
// Enter counts only a moment after that, so a key already on its way doesn't answer it.
// (Not named *Menu.qml: shell.qml treats those as top bar menus.)
PanelWindow {
    id: win
    readonly property int idleBeforeGrab: 1     // seconds without input before the card takes the keyboard
    readonly property int armDelay: 700         // ms after the card appears (a click) or gets the keyboard (Enter) before Allow counts

    property bool open: false
    property var req: ({})                      // { id, title, source, tool, heading?, note?, glyph, fields: [...], timeout }
    property bool grabbed: false                // the card has the keyboard
    property bool armed: false                  // a click on Allow counts now
    property bool keyArmed: false               // Enter counts now
    property int left: 0                        // seconds until the countdown refuses
    property bool scrolledToEnd: false          // a long card has been seen to its end (it stays so when scrolled back)
    // Allow counts once everything has been on screen: a short card at once, a long one once scrolled to its end.
    // Read when Allow or Enter is pressed, after armDelay, so the new card's height has been laid out by then
    readonly property bool seenAll: scrolledToEnd || flick.atEnd
    property var verdicts: ({})                 // id → allow | deny | timeout, until confirm.py collects it
    // Shown in Ask Claude's conversation instead (AskClaudeConfirm.qml), when it is in view and the request is short:
    // everything on it is on screen there at once, and its keys are Enter and Esc in Ask Claude's field. A long one
    // (a mail's text) gets this card, to be read to the end; so does a short one if the conversation goes out of view
    property bool inlined: false
    readonly property int inlineFields: 6
    Component.onCompleted: AskClaudeSession.card = win
    Connections {
        target: AskClaudeSession
        function onViewingChanged() {
            if (AskClaudeSession.viewing || !win.inlined || !win.open) return
            win.inlined = false; win.keyArmed = false; win.armed = false
            armTimer.restart()
        }
    }

    function show(path) {
        if (open) return "busy"
        reqFile.path = ""; reqFile.path = path
        const text = reqFile.text()
        let r
        try { r = JSON.parse(text) } catch (e) { return "bad" }
        if (!r || typeof r.id !== "string" || !Array.isArray(r.fields)) return "bad"
        req = r
        left = Math.max(5, r.timeout || 60)
        const f = Hyprland.focusedMonitor
        screen = (f && Quickshell.screens.find(s => s.name === f.name)) || Quickshell.screens[0]
        grabbed = false; armed = false; keyArmed = false
        flick.contentY = 0
        scrolledToEnd = false
        inlined = AskClaudeSession.viewing && r.fields.length <= inlineFields && r.fields.every(f => !f.long)
        open = true
        armTimer.restart()
        if (inlined) keyTimer.restart()   // Ask Claude's toast has the keyboard: Enter counts after the same moment
        return "shown " + Qt.md5(text)
    }
    function decide(v) {
        if (!open) return
        verdicts[req.id] = v
        open = false; grabbed = false; armed = false; keyArmed = false; inlined = false
        armTimer.stop(); keyTimer.stop()
    }
    function grab() {
        if (!open || grabbed) return
        grabbed = true
        keys.forceActiveFocus()
        keyTimer.restart()
    }

    IpcHandler {
        target: "claudeConfirm"
        function open(path: string): string { return win.show(path) }
        function answer(id: string): string {
            if (id in win.verdicts) {
                const v = win.verdicts[id]
                delete win.verdicts[id]
                return v
            }
            return win.open && win.req.id === id ? "pending" : "gone"
        }
        function close(id: string): void { if (win.open && win.req.id === id) win.decide("deny") }
    }

    FileView { id: reqFile; blockLoading: true; printErrors: false }

    // Input elsewhere keeps it from being idle: the card takes the keyboard once the typing has stopped
    IdleMonitor {
        enabled: win.open && !win.grabbed && !win.inlined
        timeout: win.idleBeforeGrab
        respectInhibitors: false   // a video playing mustn't hold the keyboard back, nor give it away
        onIsIdleChanged: if (isIdle) win.grab()
    }
    Timer { id: armTimer; interval: win.armDelay; onTriggered: win.armed = true }
    Timer { id: keyTimer; interval: win.armDelay; onTriggered: win.keyArmed = true }
    Timer {
        running: win.open
        interval: 1000; repeat: true
        onTriggered: if (--win.left <= 0) win.decide("timeout")
    }

    visible: open && !inlined
    color: "transparent"
    implicitWidth: card.width
    implicitHeight: card.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: grabbed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "claude-confirm"

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            const page = flick.height - 40
            if (e.key === Qt.Key_Escape) win.decide("deny")
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (!e.isAutoRepeat && win.keyArmed && win.seenAll) win.decide("allow") }
            else if (e.key === Qt.Key_Down) flick.scrollBy(40)
            else if (e.key === Qt.Key_Up) flick.scrollBy(-40)
            else if (e.key === Qt.Key_PageDown || e.key === Qt.Key_Space) flick.scrollBy(page)
            else if (e.key === Qt.Key_PageUp) flick.scrollBy(-page)
            else return
            e.accepted = true
        }
    }

    Rectangle {
        id: card
        width: Math.min(560, (win.screen ? win.screen.width : 600) - 32)
        height: body.implicitHeight + 36
        radius: 14
        color: Theme.launcherBg
        border { color: Theme.warning; width: 1 }
        // A click anywhere on the card gives it the keyboard
        MouseArea { anchors.fill: parent; onPressed: win.grab() }

        Column {
            id: body
            x: 18; y: 18
            width: parent.width - 36
            spacing: 14

            Row {
                width: parent.width
                spacing: 10
                Text {
                    id: glyph
                    width: 36
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: Icons.g(win.req.glyph || "shield-alert")
                    color: Theme.warning
                    font { family: Icons.familyThin; pixelSize: 30 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - glyph.width - 10
                    spacing: 2
                    Text {
                        width: parent.width
                        // An act's title says what it does ("Send an email"); an Ask names the kind, then the tool
                        text: win.req.heading || "Claude asks to: " + (win.req.title || "")
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.title
                        font { family: Theme.font; pixelSize: 14; bold: true }
                    }
                    Text {
                        width: parent.width
                        text: (win.req.source || "") + " · " + ((win.req.heading ? win.req.title : win.req.tool) || "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.dim
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
            }

            // Every argument, scrolling when they don't fit in most of the screen
            Item {
                width: parent.width
                height: Math.min(fields.implicitHeight, (win.screen ? win.screen.height : 800) * 0.6)
                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentHeight: fields.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    function scrollBy(d) { contentY = Math.max(0, Math.min(contentHeight - height, contentY + d)) }
                    readonly property bool atEnd: contentY + height >= contentHeight - 1
                    // Only a scroll the user made counts (show() puts contentY back to 0 while the old card's height
                    // may still be laid out). Not atEnd here: this handler can run before that binding is updated
                    onContentYChanged: if (contentY > 0 && contentY + height >= contentHeight - 1) win.scrolledToEnd = true
                    Column {
                        id: fields
                        width: flick.width
                        spacing: 10
                        Repeater {
                            model: win.req.fields || []
                            ClaudeConfirmField {
                                required property var modelData
                                width: fields.width
                                entry: modelData
                            }
                        }
                        Text {
                            visible: (win.req.fields || []).length === 0
                            text: "No details: the tool takes no arguments."
                            color: Theme.dim
                            font { family: Theme.font; pixelSize: 12 }
                        }
                    }
                }
                // More below: the bottom fades while there is more to scroll to
                Rectangle {
                    visible: flick.contentY + flick.height < flick.contentHeight - 1
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 40
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Theme.launcherBg }
                    }
                }
            }

            // What follows from allowing it: a read goes to Anthropic, a change can be undone, a delete maybe not
            Text {
                visible: !!win.req.note
                width: parent.width
                text: win.req.note || ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.dim
                font { family: Theme.font; pixelSize: 12 }
            }

            Item {
                width: parent.width
                height: 38
                ClaudeWriteButton {
                    id: deny
                    anchors.bottom: parent.bottom
                    keys: ["Esc"]; label: "Deny"
                    onClicked: win.decide("deny")
                }
                Text {
                    anchors { left: deny.right; leftMargin: 12; right: allowButton.left; rightMargin: 12
                              verticalCenter: deny.verticalCenter }
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    // Not the keyboard yet after a moment: someone is typing elsewhere
                    text: (!win.grabbed && win.left < (win.req.timeout || 60) - 1 ? "Click or stop typing to answer · "
                           : !win.seenAll ? "Scroll to the end to allow · " : "") + "Denied in " + win.left + " s"
                    color: win.left <= 10 ? Theme.warning : Theme.dim
                    font { family: Theme.font; pixelSize: 11 }
                }
                ClaudeWriteButton {
                    id: allowButton
                    anchors { right: parent.right; bottom: parent.bottom }
                    keys: ["Enter"]; label: "Allow"; strong: true
                    opacity: win.armed && win.seenAll ? 1 : 0.4
                    onClicked: if (win.armed && win.seenAll) win.decide("allow")
                }
            }
        }
    }
}
