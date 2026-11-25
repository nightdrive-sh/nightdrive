import QtQuick
import qs

// What just happened (Copied, Saved to Google, Moved to Archive), in a rounded card at the top of the window, over
// whatever is there. A quiet line under the list went unnoticed (#1640); at the top, in the middle, it is seen without
// asking for anything. It goes by itself after duration, or stays (sticky) for what takes a while and tells when it is
// done, such as a sync: the next show() replaces it. A click dismisses it. danger is for a failure, in the danger colour
// and longer, as it may need reading. An action (Undo), or a few (Open, Show in folder), are buttons at its right end,
// and the card stays longer, to be reached: the words are cut short before they are. Put it last in the window (or give it a z) so it shows over a panel too.
Rectangle {
    id: root
    required property QtObject c
    property int duration: 4000             // ms on show for a plain notice
    property int dangerDuration: 8000       // a failure stays longer: it is more to read and may matter
    property int actionDuration: 7000       // with an action: time to read it and move the pointer there
    property int topMargin: 14
    property string text: ""
    property bool danger: false
    property var actions: []                // the buttons: [{ label, run }], [] for none
    readonly property string action: actions.length ? actions[0].label : ""   // the first's word (act() runs it)
    readonly property bool shown: text !== ""

    // opts: { sticky, danger, duration, action: "Undo", run: function } or, for more than one button,
    // actions: [{ label, run }]. An empty text hides it.
    function show(t, opts) {
        const o = opts || {}
        danger = !!o.danger
        actions = o.actions ? o.actions.filter(a => a.label && a.run) : o.action && o.run ? [{ label: o.action, run: o.run }] : []
        text = t || ""
        if (text === "" || o.sticky) timer.stop()
        else { timer.interval = o.duration || (danger ? dangerDuration : action ? actionDuration : duration); timer.restart() }
    }
    function hide() { timer.stop(); text = ""; actions = [] }
    // The first button's work, for a key that does the same (⌘Z): false when the toast offers none now
    function act() { return run(0) }
    function run(i) {
        const a = actions[i]
        if (!shown || !a) return false
        hide()
        a.run()
        return true
    }

    // The last text stays in the card while it fades, so it doesn't shrink to nothing on its way out
    property string held: ""
    property var heldActions: []
    onTextChanged: if (text !== "") { held = text; heldActions = actions }

    anchors.horizontalCenter: parent.horizontalCenter
    y: shown ? topMargin : topMargin - 10
    z: 100
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // As wide as its words, up to the window's width less a margin: a longer one is cut short (elided)
    readonly property int glyphRoom: danger ? glyph.implicitWidth + 9 : 0
    readonly property int actionRoom: heldActions.length ? buttons.width + 10 : 0
    width: Math.min(glyphRoom + label.implicitWidth + actionRoom + 36, parent.width - 48)
    height: 36
    radius: height / 2
    color: Qt.lighter(c.solid, 1.35)        // a shade over the window, so it is seen without a shadow
    border.color: danger ? Qt.rgba(c.danger.r, c.danger.g, c.danger.b, 0.5) : c.line

    Timer { id: timer; onTriggered: root.text = "" }

    // Takes the click on itself only: the window around it stays clickable
    // (not on an action's button, whose own tap runs it: which of the two handlers hears the tap first isn't promised)
    TapHandler {
        onTapped: (point) => {
            const p = buttons.mapFromItem(root, point.position)
            if (!(buttons.visible && buttons.contains(p))) root.hide()
        }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }

    Text {
        id: glyph
        visible: root.danger
        x: 18; anchors.verticalCenter: parent.verticalCenter
        text: Icons.g("triangle-alert"); font.family: Icons.family; font.pixelSize: 13
        color: root.c.danger
    }
    Text {
        id: label
        x: 18 + root.glyphRoom; anchors.verticalCenter: parent.verticalCenter
        width: root.width - 36 - root.glyphRoom - root.actionRoom
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.held
        color: root.c.text; font.family: root.c.font; font.pixelSize: 12
    }
    // The actions at the right end, in the accent: each its own tap, so it doesn't only dismiss the card
    Row {
        id: buttons
        visible: root.heldActions.length > 0
        anchors.right: parent.right; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Repeater {
            model: root.heldActions
            delegate: Rectangle {
                id: button
                required property var modelData
                required property int index
                width: word.implicitWidth + 24
                height: root.height - 12
                radius: height / 2
                color: press.hovered ? Qt.rgba(root.c.accent.r, root.c.accent.g, root.c.accent.b, 0.28)
                                     : Qt.rgba(root.c.accent.r, root.c.accent.g, root.c.accent.b, 0.16)
                Text {
                    id: word
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: button.modelData.label
                    color: root.c.accent; font.family: root.c.font; font.pixelSize: 12; font.weight: Font.Medium
                }
                HoverHandler { id: press; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.run(button.index) }
            }
        }
    }
}
