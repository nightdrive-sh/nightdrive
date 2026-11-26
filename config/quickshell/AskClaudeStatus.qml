import QtQuick

// Ask Claude's toast while it's closed (AskClaudeToast.qml, Dashboard #1895): one line in a small card, so you see
// Claude is still at it after Esc, and when it has answered, without a notification:
//   🤖 Claude is working · Searching Deck…        (the robot breathes)
//   🤖 Claude answered: Jazz plays now in …       (for a while, then the card goes; the launcher's row still says so)
// A click on the card opens the toast again (the toast handles it); while Claude works, the ✕ at its end cancels the
// turn (AskClaudeSession.stop(): its unit stops, #2244). When the answered turn changed something (a task added, the
// volume set), Undo at its end takes all of it back, as the changes' notification does (#3157):
//   🤖 Claude answered: Added the task …   Undo   →   🤖 Undid: Added the task …
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
    // How it ended: the answer's first line, or the error. The turn's "results" entry (its cards, #2245) comes after
    // the answer and says nothing here
    readonly property var last: session.entries.filter(e => e.kind !== "results").slice(-1)[0] || ({})
    readonly property string firstLine: ((last.text || "").split("\n").find(l => l.trim() !== "") || "").trim()

    readonly property int cancelWidth: session.busy ? 30 : 0   // the ✕ and its gap
    readonly property bool undoShown: session.undoable || session.undoState === "run"
    readonly property int undoWidth: undoShown ? undo.implicitWidth + 18 : 0
    readonly property int endWidth: cancelWidth + undoWidth
    readonly property bool holding: undoArea.containsMouse   // the pointer on Undo: the card waits for the click
    implicitWidth: Math.min(maxWidth, 16 + glyph.implicitWidth + 10 + label.implicitWidth + 18 + endWidth)
    implicitHeight: 48

    Text {
        id: glyph
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        text: Icons.g(st.session.thinkingGlyph)
        color: (st.last.kind === "error" || st.session.undoState === "error") && !st.session.busy ? Theme.warning
                                                                                                 : Theme.accent
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
        width: Math.min(implicitWidth, st.maxWidth - 16 - glyph.implicitWidth - 10 - 18 - st.endWidth)
        elide: Text.ElideRight
        textFormat: Text.StyledText
        // The state bright, its detail dim: what you glance at first
        readonly property string head: st.session.busy ? "Claude is working"
                                     : st.session.undoState === "done" ? "Undid"
                                     : st.session.undoState === "error" ? "Couldn't undo"
                                     : st.last.kind === "error" ? "Claude couldn't answer"
                                     : st.session.look === "unsure" ? "Claude asks" : "Claude answered"
        readonly property string tail: st.session.busy ? st.doing
                                     : /^(done|error)$/.test(st.session.undoState) ? st.session.undoNote
                                     : st.last.kind === "error" ? "" : st.firstLine
        text: esc(head) + (tail !== "" ? "<font color='" + Theme.dim + "'>" + (st.session.busy ? "  ·  " : ": ")
                                         + esc(tail) + "</font>" : "")
        function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
        color: Theme.text
        font { family: Theme.font; pixelSize: 13 }
    }
    // Cancel: above the toast's own click (Toast.qml's MouseArea is under its body)
    Text {
        id: cancel
        visible: st.session.busy
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        text: Icons.g("x")
        color: cancelArea.containsMouse ? Theme.warning : Theme.dim
        font { family: Icons.family; pixelSize: 16 }
        MouseArea {
            id: cancelArea
            anchors { fill: parent; margins: -8 }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: st.session.stop()
        }
    }
    // Undo, the turn's changes (AskClaudeSession.undoTurn): above the toast's own click, as Cancel is
    Text {
        id: undo
        visible: st.undoShown
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        readonly property bool running: st.session.undoState === "run"
        text: running ? "Undoing…" : "Undo"
        color: running ? Theme.dim : undoArea.containsMouse ? Theme.text : Theme.accent
        font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        MouseArea {
            id: undoArea
            anchors { fill: parent; margins: -8 }
            hoverEnabled: true
            enabled: !undo.running
            cursorShape: Qt.PointingHandCursor
            onClicked: st.session.undoTurn()
        }
    }
}
