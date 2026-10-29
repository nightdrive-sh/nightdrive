import QtQuick

// Ask Claude's conversation as it goes (AskClaudeSession): your requests in a darker box, each step Claude takes as a
// row with its glyph (pulsing while it runs, dim once done, red with ✕ when it failed), a robot's head while it thinks, and its answer's text as it is written.
// It knows nothing of the launcher, so another place can show it: give it a width, maxHeight and the font.
Item {
    id: t
    property int maxHeight: 400
    property int fontSize: 17
    property int fontWeight: Font.Light

    // --- Tunables ---
    readonly property int stepHeight: 30
    readonly property int inset: 14      // text starts here, as in the search field and the request's box
    readonly property int textX: inset + 28   // Claude's part: the steps' and answers' text, after their glyph
    readonly property int gap: 10

    readonly property var session: AskClaudeSession
    readonly property bool thinking: session.busy && session.live === "" && !session.entries.some(e => e.kind === "step" && e.state === "run")
    implicitHeight: Math.min(col.implicitHeight, maxHeight)
    clip: true

    // A step's glyph and text, or the thinking row's
    component StepRow: Row {
        property string glyph: ""
        property string text: ""
        property string phase: "done"   // run | done | error | stop (not `state`: Item has one)
        spacing: 12
        height: t.stepHeight
        Text {
            id: mark
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g(parent.glyph)
            color: parent.phase === "error" ? Theme.danger : parent.phase === "run" ? Theme.accent : Theme.dim
            font { family: Icons.family; pixelSize: 16 }
            SequentialAnimation on opacity {
                running: mark.parent.phase === "run"; loops: Animation.Infinite
                onStopped: mark.opacity = 1
                NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: t.width - t.inset - 28 - (tail.visible ? tail.width + 12 : 0)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: parent.text
            color: parent.phase === "run" ? Theme.text : Theme.dim
            font { family: Theme.font; pixelSize: t.fontSize - 3; weight: t.fontWeight }
        }
        Text {
            id: tail
            visible: parent.phase === "error"   // done needs no mark: the glyph stops pulsing and dims
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g("x")
            color: Theme.danger
            font { family: Icons.family; pixelSize: 14 }
        }
    }
    component Said: Text {
        width: t.width
        leftPadding: t.inset
        rightPadding: t.inset
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: Theme.text
        font { family: Theme.font; pixelSize: t.fontSize; weight: t.fontWeight }
    }
    // Claude's own words: the robot's head beside them, the text a little smaller than the field's and in line with the
    // steps' text; an error (no glyph) in the same place
    component Answer: Item {
        property string text: ""
        property string glyph: t.session.thinkingGlyph
        property color color: Theme.text
        width: t.width
        height: body.implicitHeight
        Text {
            visible: parent.glyph !== ""
            x: t.inset - 4
            width: 20
            y: body.topPadding + (lineMetrics.height - height) / 2
            horizontalAlignment: Text.AlignHCenter
            text: Icons.g(parent.glyph)
            color: Theme.accent
            font { family: Icons.family; pixelSize: 16 }
        }
        Said {
            id: body
            topPadding: 4
            leftPadding: t.textX
            text: parent.text
            color: parent.color
            font.pixelSize: t.fontSize - 2
        }
        FontMetrics { id: lineMetrics; font: body.font }
    }

    Flickable {
        id: view
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        // The newest stays in view as the conversation grows
        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
        onHeightChanged: contentY = Math.max(0, contentHeight - height)
        TouchScroll { view: view; step: t.stepHeight }

        Column {
            id: col
            width: t.width
            spacing: 4
            bottomPadding: t.gap      // room under the last message, before the footer
            Repeater {
                model: t.session.entries
                Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property string kind: modelData.kind
                    width: t.width
                    // A request opens a new exchange: a little room above it after the first, and below it before Claude's part
                    readonly property int above: kind === "you" && index > 0 ? t.gap : 0
                    height: above + (kind === "you" ? you.height + t.gap : kind === "step" ? t.stepHeight : said.height + 6)
                    Rectangle {
                        id: you
                        visible: entry.kind === "you"
                        y: entry.above
                        width: t.width
                        height: youText.implicitHeight + 20
                        radius: 10
                        color: Theme.card
                        Said {
                            id: youText
                            y: 10
                            text: entry.kind === "you" ? entry.modelData.text : ""
                            color: Theme.muted
                            font.pixelSize: t.fontSize - 2
                        }
                    }
                    StepRow {
                        visible: entry.kind === "step"
                        x: t.inset - 4
                        glyph: entry.modelData.glyph || ""
                        text: entry.modelData.text || ""
                        phase: entry.modelData.state || "done"
                    }
                    Answer {
                        id: said
                        visible: entry.kind === "text" || entry.kind === "error"
                        text: visible ? entry.modelData.text : ""
                        glyph: entry.kind === "error" ? "" : t.session.thinkingGlyph
                        color: entry.kind === "error" ? Theme.warning : Theme.text
                    }
                }
            }
            StepRow {
                visible: t.thinking
                x: t.inset - 4
                glyph: t.session.thinkingGlyph
                text: "Thinking…"
                phase: "run"
            }
            Answer {
                visible: t.session.live !== ""
                text: t.session.live.trim()
            }
            // Claude's card for a short request (Enter and Esc in the field answer it): a little inside your request's
            // box's edges (its border would stand out beside the box), with room above and below
            Item {
                visible: t.session.pendingCard
                width: t.width
                height: confirmCard.height + 2 * t.gap + 6
                AskClaudeConfirm {
                    id: confirmCard
                    x: 4
                    y: t.gap + 6
                    width: t.width - 2 * x
                    card: t.session.card
                    fontSize: t.fontSize
                }
            }
        }
    }
}
