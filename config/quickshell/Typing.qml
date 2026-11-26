import QtQuick
import Quickshell.Io

// Whether the user is typing, by the rule Claude's window tools keep (hypr/last-key.lua: NightdriveTyping, a key in the
// last 1–2 s; hypr/scripts/windows: not_typing), so the confirmation card and the tools agree on what a pause is
// (Dashboard #1987). Only keys count, as for the tools: moving the mouse isn't typing.
// While `active`, Hyprland is asked a few times a second; `paused()` fires when the typing stops, and at once when
// there was none. Each activation starts from "typing", so a card shown again, or in another place, waits for a pause
// of its own. An answer that can't be read counts as typing: the card then keeps its hands off the keyboard, and a
// click on it still answers. reset(): a key seen here (Ask Claude's field) is typing, whatever an ask already on its
// way answers, so a stale "no" can't make a pause of it.
Item {
    id: t
    property bool active: false
    property bool typing: true
    readonly property int pollMs: 250   // a pause shows within this; one ask is a hyprctl call
    property int round: 0               // bumped by reset(): answers to asks made before it are dropped
    property int asked: 0               // the round the running ask was made in
    signal paused()

    function reset() { round++; typing = true }
    onActiveChanged: reset()

    Timer {
        interval: t.pollMs; repeat: true; triggeredOnStart: true
        running: t.active
        onTriggered: if (!ask.running) { t.asked = t.round; ask.running = true }
    }
    Process {
        id: ask
        command: ["hyprctl", "repl", "return NightdriveTyping()"]
        stdout: StdioCollector {
            onStreamFinished: {
                // An answer that arrives once the card has gone, or from before a reset, says nothing
                if (!t.active || t.asked !== t.round) return
                const now = text.trim() !== "false"
                if (t.typing && !now) { t.typing = false; t.paused() }
                else t.typing = now
            }
        }
    }
}
