import QtQuick
import qs
import qs.kit

// The message's own buttons, as its sender named them: open a file or folder, an address, a session, a task, or run a
// command. A run button shows its whole command while the pointer is on it, in a monospaced card under it laid over
// what follows (nothing moves), and a click on it only asks (RunPanel), where the command and its folder are shown
// again in full: it never runs from here. The others do what they say at once (press).
Flow {
    id: root
    required property QtObject c
    property var actions: []             // Store.message.actions (a run one with its line: cli.py's full())
    signal press(int index)
    signal ask(int index)                // a run button: its card first
    spacing: 10
    z: 3                                 // a command's card over the text under the buttons
    readonly property var glyphs: ({ open: "folder-open", url: "external-link", run: "square-terminal",
                                     session: "bot", task: "list-checks" })
    function tipOf(a) {
        return a.kind === "open" ? a.path : a.kind === "url" ? a.url : a.kind === "session" ? "Go to the session"
            : a.kind === "task" ? "Open task #" + a.task : ""
    }

    Repeater {
        model: root.actions
        delegate: AppButton {
            id: button
            required property var modelData
            required property int index
            readonly property bool run: modelData.kind === "run"
            z: hovered ? 1 : 0
            c: root.c; glyph: root.glyphs[modelData.kind] || "circle"; label: modelData.label
            tip: root.tipOf(modelData); tipAlign: "left"
            onClicked: run ? root.ask(index) : root.press(index)

            // The command, from the button's left edge, as wide as the buttons' row at most (a long one wraps)
            Rectangle {
                visible: button.run && button.hovered
                x: 0; y: button.height + 6
                width: Math.min(line.implicitWidth + 20, root.width - button.x)
                height: line.implicitHeight + 12
                radius: 6
                color: root.c.solid
                border.width: 1; border.color: root.c.divider
                Text {
                    id: line
                    x: 10; y: 6
                    width: Math.min(implicitWidth, root.width - button.x - 20)
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.PlainText
                    text: button.run ? "Run: " + button.modelData.line : ""
                    font.family: "monospace"; font.pixelSize: 11
                    color: root.c.text
                }
            }
        }
    }
}
