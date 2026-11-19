import QtQuick
import qs
import qs.kit

// The message's own buttons, as its sender named them: open a file or folder, an address, a session, a task, or run a
// command. A run button has its whole command under it, in a monospaced line, so what it does is never hidden behind
// its label; a click on it only asks (RunPanel), it never runs. The others do what they say at once (press).
Flow {
    id: root
    required property QtObject c
    property var actions: []             // Store.message.actions (a run one with its line: cli.py's full())
    signal press(int index)
    signal ask(int index)                // a run button: its card first
    spacing: 10
    readonly property var glyphs: ({ open: "folder-open", url: "external-link", run: "square-terminal",
                                     session: "bot", task: "list-checks" })
    function tipOf(a) {
        return a.kind === "open" ? a.path : a.kind === "url" ? a.url : a.kind === "session" ? "Go to the session"
            : a.kind === "task" ? "Open task #" + a.task : "Shows the command and its folder first"
    }

    Repeater {
        model: root.actions
        delegate: Column {
            id: cell
            required property var modelData
            required property int index
            readonly property bool run: modelData.kind === "run"
            spacing: 4
            // As wide as the view at most: a long command wraps under its button instead of running out of it
            width: run ? Math.min(root.width, Math.max(button.implicitWidth, line.implicitWidth)) : button.implicitWidth
            AppButton {
                id: button
                c: root.c; glyph: root.glyphs[cell.modelData.kind] || "circle"; label: cell.modelData.label
                strong: cell.index === 0
                tip: root.tipOf(cell.modelData); tipAlign: "left"
                onClicked: cell.run ? root.ask(cell.index) : root.press(cell.index)
            }
            Text {
                id: line
                visible: cell.run
                width: Math.min(implicitWidth, root.width)
                wrapMode: Text.WrapAnywhere
                textFormat: Text.PlainText
                text: cell.run ? "$ " + cell.modelData.line : ""
                font.family: "monospace"; font.pixelSize: 11
                color: root.c.dim
            }
        }
    }
}
