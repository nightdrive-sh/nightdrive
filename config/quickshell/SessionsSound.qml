import QtQuick
import Quickshell

// The sessions bar's sounds (#3743): a soft rising fourth when a Claude Code session starts to ask you something, a
// falling one when it has finished its task (its last line "✅ …"), the moment its chip changes (Claude.seen). Only
// while the bar is there for you to see (Claude.barShown): otherwise claude-notify's notification carries the news,
// with its own sound. Never for the session whose window you're in, nor with do not disturb on. Several at once (a
// shell reload aside: a session seen for the first time plays nothing) gather into one sound, the question's if any.
// hypr/scripts/sounds plays it, unless Settings › Notifications › Sessions bar sound is off.
QtObject {
    id: snd
    required property var claude
    property var was: ({})          // address → "asking" | "done" | "" as last seen
    property string pending: ""     // the sound to play once the burst is over

    function news(s) { return s.asking ? "asking" : s.done ? "done" : "" }

    property Connections watch: Connections {
        target: snd.claude
        function onSeenChanged() {
            const now = {}
            for (const s of snd.claude.seen) {
                const n = snd.news(s)
                now[s.address] = n
                if (!n || !(s.address in snd.was) || snd.was[s.address] === n) continue
                if (s.address === snd.claude.activeAddr) continue
                if (snd.pending !== "asking") snd.pending = n
                gather.restart()
            }
            snd.was = now
        }
    }

    // The scan and the titles change a moment apart: wait for the rest of a burst, then play one
    property Timer gather: Timer {
        id: gather
        interval: 700
        onTriggered: {
            const n = snd.pending
            snd.pending = ""
            if (!n || !snd.claude.barShown || Notifs.dnd) return
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "session", n])
        }
    }
}
