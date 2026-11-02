import QtQuick
import Quickshell
import qs.kit

// A message window: the thread, with the reading keys and replies of its own. Esc or ⌘W closes it. Apart from
// shell.qml, which opens one for a double click or Enter in the list (win.openWindow).
FloatingWindow {
    id: mw
    required property var win
    required property var ops           // Actions.qml
    property var msgs: []
    property int htmlMode: win.settings.view
    property bool opening: win.settings.composeFloats
    title: msgs.length ? msgs[0].subject || "(no subject)" : "Message"
    implicitWidth: 820
    implicitHeight: 900
    minimumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(360, 300)
    maximumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(0, 0)
    Timer { running: true; interval: 400; onTriggered: mw.opening = false }
    color: win.look.bg
    visible: true
    onClosed: destroy()
    function scroll(dy) { thread.cancelFlick(); thread.contentY = Math.max(0, Math.min(thread.contentHeight - thread.height, thread.contentY + dy)) }

    Thread {
        id: thread
        anchors.fill: parent
        app: win; c: app.look; nm: app.mailer
        messages: mw.msgs
        htmlMode: mw.htmlMode
        onCycleHtml: mw.htmlMode = (mw.htmlMode + 1) % 3
        onOpenBrowser: win.openBrowser(mw.msgs)
        onResumeDraft: win.compose("resume", mw.msgs)
        actions: ops.windowActions
        onAct: id => ops.act(id, mw.msgs)
        focus: true
        Keys.onPressed: e => {
            const k = e.key
            keys.pressed(e)             // ? and Ctrl+? show and hide the keys
            if (k === Qt.Key_Question) {}
            else if (thread.isCopy(e)) thread.copy()
            else if (k === Qt.Key_Escape) mw.visible = false
            else if (k === Qt.Key_Down) mw.scroll(win.arrowStep)
            else if (k === Qt.Key_Up) mw.scroll(-win.arrowStep)
            else if (k === Qt.Key_Space) mw.scroll((e.modifiers & Qt.ShiftModifier ? -1 : 1) * (thread.height - 80))
            else if (k === Qt.Key_H && e.modifiers & Qt.ShiftModifier) win.openBrowser(mw.msgs)
            else if (k === Qt.Key_H) mw.htmlMode = (mw.htmlMode + 1) % 3
            else if (k === Qt.Key_R) win.compose(e.modifiers & Qt.ShiftModifier ? "reply" : "all", mw.msgs)
            else if (k === Qt.Key_F) win.compose("forward", mw.msgs)
            else return
            e.accepted = true
        }
    }
    Shortcut { sequences: ["Meta+Shift+C", "Ctrl+Shift+C"]; onActivated: win.compose("claude", mw.msgs) }
    KeySheet {
        id: keys
        c: win.look
        groups: [
            { title: "Read", keys: [["↑ ↓", "Scroll"], ["Space ⇧Space", "Page down, up"], ["h", "HTML or text"], ["⇧H", "HTML in the browser"], ["Esc  ⌘W", "Close the window"]] },
            { title: "Write", keys: [["r", "Reply to all"], ["⇧R", "Reply to the sender only"], ["f", "Forward"], ["⌘⇧C", "Claude writes the reply"]] }
        ]
    }
    onVisibleChanged: if (!visible) destroy()
}
