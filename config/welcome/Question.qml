import QtQuick
import qs
import qs.kit

// Welcome's first question: Claude, with a Pro or Max plan? Yes sets each thing up in a Claude session of its own (as
// TaskList's rows do), No by hand in the window (StepView). The answer is setup.json's path, changed later by c in the list.
Item {
    id: root
    required property var app
    required property QtObject c
    property int current: 0
    signal chosen(string path)

    readonly property var choices: [
        { path: "claude", icon: "sparkles", name: "Yes, I have Claude",
          about: "Claude sets each one up with you, in a terminal over this window, and explains it as you go." },
        { path: "manual", icon: "list-checks", name: "No, I don't have Claude",
          about: "I'll set things up myself: step-by-step instructions here, in plain words." }
    ]
    // What waits, by name: "Tailscale, Mail and Deck"
    readonly property string waiting: {
        const n = app.tasks.filter(t => t.id !== "claude").map(t => t.name)
        return n.length < 2 ? n.join("") : n.slice(0, -1).join(", ") + " and " + n[n.length - 1]
    }

    function key(e) {
        const k = e.key
        if (k === Qt.Key_Down || k === Qt.Key_J) current = 1
        else if (k === Qt.Key_Up || k === Qt.Key_K) current = 0
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) chosen(choices[current].path)
        else if (k === Qt.Key_Y) chosen("claude")
        else if (k === Qt.Key_N) chosen("manual")
        else if (k === Qt.Key_Escape) app.close()
        else return false
        return true
    }

    Column {
        id: head
        x: 40; y: 40
        width: parent.width - 80
        spacing: 16
        AppTitle { c: root.c; text: "Welcome to Nightdrive"; pixelSize: 24 }
        Text {
            width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.25
            color: root.c.text; font.family: root.c.font; font.pixelSize: 13
            // The user's own words (5226e6c), with what waits named
            text: "Your new computer is almost ready. To get the most out of Nightdrive, we recommend setting up the "
                + "rest with Claude Code" + (root.waiting ? ": " + root.waiting : "") + ". If you don't have Claude, or "
                + "want to skip for now, you can come back later from the launcher › System › Set up Nightdrive."
        }
        Text {
            topPadding: 8
            width: parent.width; wrapMode: Text.Wrap
            color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
            text: "Do you have Claude, with a Pro or Max plan?"
        }
    }

    Column {
        id: rows
        x: 26; y: head.y + head.height + 20
        width: parent.width - 52
        spacing: 2
        Repeater {
            model: root.choices
            delegate: AppRow {
                id: row
                required property var modelData
                required property int index
                width: rows.width
                c: root.c
                selected: index === root.current
                height: about.y + about.height + 12
                TapHandler { onTapped: { root.current = row.index; root.chosen(row.modelData.path) } }
                Text {
                    x: 14; y: 13
                    text: Icons.g(row.modelData.icon); font.family: Icons.family; font.pixelSize: 16
                    color: row.selected ? root.c.accent : root.c.dim
                }
                Text {
                    id: name
                    x: 44; y: 12
                    text: row.modelData.name
                    color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    id: about
                    x: 44; y: name.y + name.height + 3
                    width: row.width - x - 130
                    text: row.modelData.about; wrapMode: Text.Wrap; lineHeight: 1.15
                    color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
                }
                AppKeyAction {
                    visible: row.selected
                    x: row.width - width - 14; y: 13
                    c: root.c
                    keys: "⏎"; label: "Choose"
                    color: root.c.primary; hoverColor: root.c.title
                    onClicked: root.chosen(row.modelData.path)
                }
            }
        }
    }

    // What Claude needs, and that Nightdrive doesn't need Claude
    Text {
        x: 40; y: rows.y + rows.height + 20
        width: parent.width - 80
        wrapMode: Text.Wrap; lineHeight: 1.25
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
        text: "Claude Code needs a Pro or Max plan, or an API account. Nightdrive works without it too. With it, Claude "
            + "also helps in Nightdrive's apps: it writes replies in Mail, answers in the launcher and picks albums for Deck."
    }

    Item {
        x: 40; y: parent.height - height - 28
        width: parent.width - 80
        height: 40
        KeyCap { c: root.c; keys: "↑  ↓"; tint: root.c.faint; anchors.verticalCenter: parent.verticalCenter }
        FootButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            c: root.c
            keys: "esc"; label: "Skip for now"
            onClicked: root.app.close()
        }
    }
}
