import QtQuick
import qs

// What just happened (Copied, Saved to Google, Moved to Archive), in a rounded card at the top of the window, over
// whatever is there. A quiet line under the list went unnoticed (#1640); at the top, in the middle, it is seen without
// asking for anything. It goes by itself after duration, or stays (sticky) for what takes a while and tells when it is
// done, such as a sync: the next show() replaces it. A click dismisses it. danger is for a failure, in the danger colour
// and longer, as it may need reading. Put it last in the window (or give it a z) so it shows over a panel too.
Rectangle {
    id: root
    required property QtObject c
    property int duration: 4000             // ms on show for a plain notice
    property int dangerDuration: 8000       // a failure stays longer: it is more to read and may matter
    property int topMargin: 14
    property string text: ""
    property bool danger: false
    readonly property bool shown: text !== ""

    // opts: { sticky, danger, duration }. An empty text hides it.
    function show(t, opts) {
        const o = opts || {}
        danger = !!o.danger
        text = t || ""
        if (text === "" || o.sticky) timer.stop()
        else { timer.interval = o.duration || (danger ? dangerDuration : duration); timer.restart() }
    }
    function hide() { timer.stop(); text = "" }

    // The last text stays in the card while it fades, so it doesn't shrink to nothing on its way out
    property string held: ""
    onTextChanged: if (text !== "") held = text

    anchors.horizontalCenter: parent.horizontalCenter
    y: shown ? topMargin : topMargin - 10
    z: 100
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // As wide as its words, up to the window's width less a margin: a longer one is cut short (elided)
    readonly property int glyphRoom: danger ? glyph.implicitWidth + 9 : 0
    width: Math.min(glyphRoom + label.implicitWidth + 36, parent.width - 48)
    height: 36
    radius: height / 2
    color: Qt.lighter(c.solid, 1.35)        // a shade over the window, so it is seen without a shadow
    border.color: danger ? Qt.rgba(c.danger.r, c.danger.g, c.danger.b, 0.5) : c.line

    Timer { id: timer; onTriggered: root.text = "" }

    // Takes the click on itself only: the window around it stays clickable
    TapHandler { onTapped: root.hide() }
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
        width: root.width - 36 - root.glyphRoom
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.held
        color: root.c.text; font.family: root.c.font; font.pixelSize: 12
    }
}
