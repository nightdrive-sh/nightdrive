import QtQuick
import qs
import qs.kit

// One thing to set up in the Welcome window: its icon, name and why in plain words, and on the right where it stands
// (With Claude, Done, Skipped, Not finished, Needs Claude), or on the picked row what Enter does there: beside Done,
// dimmed, as it is secondary there (Run again), so a done row still says Done when picked (Jari's round 3). Set up by hand
// (the first question's No, or before signing in to Claude), Enter shows its steps (StepView); on the "I'll do it
// myself" path it opens the README, and the row shows only whether it is done.
AppRow {
    id: root
    required property var task
    required property int index
    property bool claudeIn: true            // signed in to Claude: the other rows' setups need it
    property bool manual: false             // the first question's No: every row by hand, and no Claude row
    property bool selfPath: false           // "I'll do it myself": every row a README
    readonly property int sideWidth: 260    // the right's room, the same on every row, so picking one doesn't rewrap its text
    signal activated()

    // Its state, from tasks' row: running and done come from the system, skipped and started from setup.json
    readonly property bool byHand: task.id !== "claude" && (manual || !claudeIn)
    readonly property string stage: task.running ? "running" : task.done ? "done" : task.mark === "skipped" ? "skipped"
                                  : selfPath ? "todo" : task.mark === "started" ? "started" : byHand ? "needs" : "todo"
    readonly property string action: selfPath ? "Open README" : ({
        running: "Show",
        done: task.id === "claude" ? "" : byHand ? "Show the steps" : "Run again",    // signed in is as far as Claude's row goes
        needs: task.steps ? "Set up by hand" : "Open the steps",
        skipped: task.id === "claude" ? "Sign in" : byHand ? "Set up by hand" : "Set up with Claude",
        started: "Continue",
        todo: task.id === "claude" ? "Sign in" : "Set up with Claude"
    })[stage]

    height: Math.max(about.y + about.height + 12, 56)
    TapHandler { onTapped: root.activated() }

    Text {
        id: glyph
        x: 14; y: 13
        text: Icons.g(root.task.icon); font.family: Icons.family; font.pixelSize: 16
        color: root.stage === "done" ? root.c.primary : root.selected ? root.c.accent : root.c.dim
    }
    Text {
        id: name
        x: 44; y: 12
        text: root.task.name
        color: root.stage === "skipped" || root.stage === "needs" && !root.manual ? root.c.dim : root.c.title
        font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
    }
    Text {
        id: about
        x: 44; y: name.y + name.height + 3
        width: root.width - x - sideWidth - 14
        text: root.task.about; wrapMode: Text.Wrap; lineHeight: 1.15
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
    }

    // The right: Enter's word on the picked row, the state on the others (Running shows its dots on both, Done its word)
    Row {
        id: side
        x: root.width - width - 14; y: 13
        spacing: 8
        BusyDots { visible: root.stage === "running"; anchors.verticalCenter: parent.verticalCenter }
        AppKeyAction {
            visible: root.selected && root.action !== ""
            c: root.c
            keys: "⏎"; label: root.action
            color: root.stage === "done" ? root.c.dim : root.c.primary; hoverColor: root.c.title
            onClicked: root.activated()
        }
        Item { visible: root.selected && root.action !== "" && root.stage === "done"; width: 8; height: 1 }
        Text {
            visible: root.stage === "done"
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g("check"); font.family: Icons.family; font.pixelSize: 13; color: root.c.primary
        }
        Text {
            visible: !root.selected || root.action === "" || root.stage === "done"
            anchors.verticalCenter: parent.verticalCenter
            text: ({ running: "With Claude", done: "Done", needs: root.manual ? "" : "Needs Claude", skipped: "Skipped",
                     started: "Not finished", todo: "" })[root.stage]
            color: root.stage === "done" ? root.c.primary : root.stage === "running" ? root.c.text : root.c.faint
            font.family: root.c.font; font.pixelSize: 12
        }
    }
}
