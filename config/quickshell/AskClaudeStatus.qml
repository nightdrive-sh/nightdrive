import QtQuick

// Ask Claude's toast while it's closed (AskClaudeToast.qml, Dashboard #1895): one line in a small card, so you see
// Claude is still at it after Esc, and when it has answered, without a notification:
//   🤖 Claude is working · Searching Deck…        (the robot breathes)
//   🤖 Claude answered: Jazz plays now in …       (for a while, then the card goes; the launcher's row still says so)
// A click on the card opens the toast again (the toast handles it).
Item {
    id: st
    property int maxWidth: 520
    readonly property var session: AskClaudeSession

    // What Claude is doing now: the running step, else writing or thinking
    readonly property string doing: {
        const run = session.entries.filter(e => e.kind === "step" && e.state === "run")
        if (run.length) return run[run.length - 1].text || ""
        return session.live !== "" ? "Writing…" : "Thinking…"
    }
    // How it ended: the answer's first line, or the error
    readonly property var last: session.entries.length ? session.entries[session.entries.length - 1] : ({})
    readonly property string firstLine: ((last.text || "").split("\n").find(l => l.trim() !== "") || "").trim()

    implicitWidth: Math.min(maxWidth, 16 + glyph.implicitWidth + 10 + label.implicitWidth + 18)
    implicitHeight: 48

    Text {
        id: glyph
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        text: Icons.g(st.session.thinkingGlyph)
        color: st.last.kind === "error" && !st.session.busy ? Theme.warning : Theme.accent
        font { family: Icons.family; pixelSize: 18 }
        SequentialAnimation on opacity {
            running: st.session.busy; loops: Animation.Infinite
            onRunningChanged: if (!running) glyph.opacity = 1
            NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }
    Text {
        id: label
        anchors { left: glyph.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
        width: Math.min(implicitWidth, st.maxWidth - 16 - glyph.implicitWidth - 10 - 18)
        elide: Text.ElideRight
        textFormat: Text.StyledText
        // The state bright, its detail dim: what you glance at first
        readonly property string head: st.session.busy ? "Claude is working"
                                     : st.last.kind === "error" ? "Claude couldn't answer" : "Claude answered"
        readonly property string tail: st.session.busy ? st.doing : st.last.kind === "error" ? "" : st.firstLine
        text: esc(head) + (tail !== "" ? "<font color='" + Theme.dim + "'>" + (st.session.busy ? "  ·  " : ": ")
                                         + esc(tail) + "</font>" : "")
        function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
        color: Theme.text
        font { family: Theme.font; pixelSize: 13 }
    }
}
