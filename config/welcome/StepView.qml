import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// One thing set up by hand, a step at a time: the plugin's steps.md, read by `steps` (its format is there). A step is
// a few plain words, maybe fields to fill in, a command or a file's template with their buttons, and a ✓ once its
// test passes. (The README is the "I'll do it myself" path's: the VM test found it too much beside a step.)
Item {
    id: root
    required property var app
    required property QtObject c
    property string taskId: ""
    property var sheet: null      // `steps ID`: { id, name, icon, steps }
    property int index: 0
    property bool copied: false
    // The fields filled in, per task, kept while the window is open: {key} in a command or template becomes its value
    property var kept: ({})
    readonly property var values: kept[taskId] || ({})
    readonly property var steps: sheet ? sheet.steps : []
    readonly property var step: steps[index] || null
    readonly property bool last: index >= steps.length - 1
    // What Enter does on this step: the file to edit, else the command, else its first button; with none, Next
    readonly property string primary: !step ? "" : step.edit ? "edit" : step.code ? "run" : step.actions.length ? "action" : ""
    readonly property string primaryLabel: ({ edit: "Open " + (step ? step.edit : "") + " in the editor",
                                              run: "Run in a terminal",
                                              action: step && step.actions.length ? step.actions[0].label : "" })[primary] || ""
    // The fields this step's command or template still needs, by their labels and steps: until they're filled in, it
    // isn't run with {email} in it
    readonly property var missing: {
        if (!step) return []
        const used = (step.code + " " + step.actions.map(a => a.arg).join(" ")).match(/\{\w+\}/g) || []
        const out = []
        steps.forEach((s, i) => s.asks.forEach(a => {
            if (used.includes("{" + a.key + "}") && !values[a.key]) out.push({ label: a.label, step: i })
        }))
        return out
    }

    onTaskIdChanged: { sheet = null; index = 0; Qt.callLater(load) }   // once the command has the id
    onIndexChanged: { copied = false; Qt.callLater(focusField, 0) }    // once the step's fields are there
    function load() { if (taskId !== "" && !loader.running) loader.running = true }
    Process {
        id: loader
        command: [root.app.dir + "/steps", root.taskId, JSON.stringify(root.values)]
        stdout: StdioCollector {
            onStreamFinished: {
                const first = root.sheet === null
                try { root.sheet = JSON.parse(text) } catch (e) { return }
                if (first) Qt.callLater(root.focusField, 0)
            }
        }
    }
    // The tests again every few seconds, as the list's are: a step done in the terminal or the browser shows by itself
    Timer { interval: 3000; repeat: true; running: root.visible && root.taskId !== ""; onTriggered: root.load() }
    Timer { id: soon; interval: 1200; onTriggered: root.load() }
    Timer { id: unCopy; interval: 1500; onTriggered: root.copied = false }

    function fill(text) { return text.replace(/\{(\w+)\}/g, (m, k) => values[k] || m) }
    function setValue(k, v) {
        const all = Object.assign({}, kept)
        all[taskId] = Object.assign({}, values)
        all[taskId][k] = v
        kept = all
    }
    function go(i) { index = Math.max(0, Math.min(i, steps.length - 1)) }
    function next() { if (last) app.finishSteps(taskId); else go(index + 1) }
    function act(kind, i) {
        if (missing.length) { go(missing[0].step); return }      // Enter takes you to the field instead
        const v = JSON.stringify(values), n = String(index)
        if (kind === "edit") app.run([app.dir + "/steps", "edit", taskId, n, v])
        else if (kind === "run") app.run([app.dir + "/steps", "run", taskId, n, v])
        else if (kind === "action") app.run([app.dir + "/steps", "action", taskId, n, String(i || 0), v])
        soon.restart()
    }
    function copy() {
        if (!step || !step.code) return
        Quickshell.execDetached(["wl-copy", "--", fill(step.code)])
        copied = true; unCopy.restart()
    }
    // A step's fields take the keyboard as it opens, the first empty one first; Enter goes on, Esc gives it back
    function focusField(i) {
        const f = fields.itemAt(i)
        if (f) f.input.forceActiveFocus(); else app.takeKeys()
    }

    function key(e) {
        const k = e.key
        if (k === Qt.Key_Left) go(index - 1)
        else if (k === Qt.Key_Right) next()
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (primary) act(primary, 0); else next() }
        else if (k === Qt.Key_Y) copy()
        else if (k === Qt.Key_Tab) focusField(0)
        else if (k === Qt.Key_Escape) app.closeSteps()
        else return false
        return true
    }

    Item {
        id: left
        anchors.fill: parent

        // ‹ Back to the list ……… Set up Mail  1/9: the way back and where you are on the same line, apart from the
        // step's own title under them (the VM test found the back button and the name too close together)
        Row {
            id: where
            x: parent.width - width - 40; anchors.verticalCenter: head.verticalCenter
            spacing: 10
            Text {
                text: root.sheet ? "Set up " + root.sheet.name : ""
                color: root.c.text; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
                anchors.baseline: count.baseline
            }
            Text {
                id: count
                text: root.steps.length ? (root.index + 1) + "/" + root.steps.length : ""
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
            }
        }
        Rectangle {
            id: head
            x: 28; y: 28
            width: backRow.implicitWidth + 24; height: 36; radius: 8
            color: back.hovered ? root.c.hover : "transparent"
            HoverHandler { id: back; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.app.closeSteps() }
            Row {
                id: backRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.g("chevron-left"); font.family: Icons.family; font.pixelSize: 18
                    color: back.hovered ? root.c.title : root.c.text
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Back to the list"
                    color: back.hovered ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 13
                }
            }
        }

        Flickable {
            id: flick
            x: 40; y: head.y + head.height + 20
            width: parent.width - 80
            height: foot.y - y - 16
            clip: true
            contentHeight: body.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: body
                width: flick.width
                spacing: 16
                Row {
                    spacing: 12
                    Text {
                        id: stepTitle
                        text: root.step ? root.step.title : ""
                        color: root.c.title; font.family: root.c.font; font.pixelSize: 18; font.weight: Font.DemiBold
                    }
                    Row {
                        visible: root.step !== null && root.step.done === true
                        anchors.verticalCenter: stepTitle.verticalCenter
                        spacing: 6
                        Text { text: Icons.g("check"); font.family: Icons.family; font.pixelSize: 13; color: root.c.primary }
                        Text { text: "Done"; font.family: root.c.font; font.pixelSize: 12; color: root.c.primary }
                    }
                }
                // A Text a paragraph: Qt's Markdown runs them together without a gap
                Column {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: root.step ? root.fill(root.step.text).split(/\n\s*\n/) : []
                        delegate: Text {
                            required property string modelData
                            width: parent.width
                            text: modelData
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap; lineHeight: 1.25
                            color: root.c.body; linkColor: root.c.primary
                            font.family: root.c.font; font.pixelSize: 13
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
                Repeater {
                    id: fields
                    model: root.step ? root.step.asks : []
                    delegate: StepField {
                        required property var modelData
                        required property int index
                        width: body.width
                        c: root.c
                        label: modelData.label
                        placeholder: modelData.placeholder
                        value: root.values[modelData.key] || ""
                        onEdited: text => root.setValue(modelData.key, text)
                        onDone: root.focusField(index + 1)
                        onPrevious: root.focusField(index - 1)
                        onLeave: root.app.takeKeys()
                    }
                }
                // The command or the template, with what's filled in so far; a long template scrolls in its box, so
                // the buttons under it stay in sight
                Rectangle {
                    visible: root.step !== null && root.step.code !== ""
                    width: parent.width
                    height: codeFlick.height + 24
                    radius: 8
                    color: "transparent"; border.color: root.c.line
                    Flickable {
                        id: codeFlick
                        x: 14; y: 12
                        width: parent.width - 28
                        height: Math.min(code.height, 160)
                        clip: true
                        contentHeight: code.height
                        boundsBehavior: Flickable.StopAtBounds
                        Text {
                            id: code
                            width: codeFlick.width
                            text: root.step ? root.fill(root.step.code) : ""
                            wrapMode: Text.WrapAnywhere; lineHeight: 1.2
                            color: root.c.text; font.family: root.c.font; font.pixelSize: 12
                        }
                    }
                }
                // The step's own buttons, as big as the window's foot: the one Enter presses is strong until its
                // step is done, then Next is
                Row {
                    spacing: 12
                    FootButton {
                        visible: root.primary !== ""
                        c: root.c
                        keys: "⏎"; label: root.missing.length ? "Fill in " + root.missing[0].label.toLowerCase() + " first"
                                                               : root.primaryLabel
                        strong: !root.missing.length && !(root.step && root.step.done)
                        onClicked: root.act(root.primary, 0)
                    }
                    FootButton {
                        visible: root.step !== null && root.step.code !== ""
                        c: root.c
                        keys: "y"; label: root.copied ? "Copied" : "Copy"
                        onClicked: root.copy()
                    }
                    Repeater {
                        model: root.step ? root.step.actions.slice(root.primary === "action" ? 1 : 0) : []
                        delegate: FootButton {
                            required property var modelData
                            required property int index
                            c: root.c
                            label: modelData.label
                            glyph: modelData.kind === "open" ? "external-link" : "terminal"
                            onClicked: root.act("action", index + (root.primary === "action" ? 1 : 0))
                        }
                    }
                }
            }
        }

        // Back on the left, Next big on the right, where the VM test looked for it
        Item {
            id: foot
            x: 40; y: parent.height - height - 28
            width: parent.width - 80
            height: 40
            FootButton {
                visible: root.index > 0
                anchors.verticalCenter: parent.verticalCenter
                c: root.c; keys: "←"; label: "Back"
                onClicked: root.go(root.index - 1)
            }
            FootButton {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                c: root.c; keys: "→"; label: root.last ? "Finish" : "Next"; glyph: root.last ? "check" : "arrow-right"
                strong: root.primary === "" || root.step !== null && root.step.done === true
                onClicked: root.next()
            }
        }
    }
}
