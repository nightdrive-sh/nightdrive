import QtQuick

// Horizontal slider, value 0..1.
Item {
    id: s
    property real value: 0
    property bool dimmed: false
    property color trackColor: Theme.border   // the unfilled part; on a selected row (Theme.sel) it needs to be darker
    property real level: -1                   // optional input level meter 0..1 as a row of pills under the track (-1 = none)
    property bool readOnly: false             // a meter: no knob, can't be dragged (e.g. a battery level)
    property color fillColor: Theme.accent
    readonly property bool pressed: area.pressed
    // While held, the knob follows the mouse even if `value` lags behind (or the owner holds back updates during a drag)
    property real dragValue: -1
    readonly property real shown: area.pressed && dragValue >= 0 ? dragValue : value
    signal moved(real v)

    height: 20
    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 6; radius: 3
        color: s.trackColor
        Rectangle {
            width: parent.width * Math.min(1, Math.max(0, s.shown))
            height: parent.height; radius: 3
            color: s.dimmed ? Theme.off : s.fillColor
        }
        Rectangle {
            visible: !s.readOnly
            x: parent.width * Math.min(1, Math.max(0, s.shown)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 7
            color: Theme.text
        }
    }
    // Level meter: a classic segmented meter just under the track. It hangs a few pixels below the slider's height, into
    // the spacing of the menu's Column, so the row's layout doesn't change. The scale is -60..0 dB: yellow from -12 dB, red from -3 dB (close to clipping).
    Row {
        id: meter
        visible: s.level >= 0
        x: track.x
        y: track.y + track.height + 6
        spacing: 3
        // About 12 px pills, stretched so the row is exactly as wide as the track
        readonly property int count: Math.max(1, Math.round((track.width + spacing) / (12 + spacing)))
        readonly property real pill: (track.width - spacing * (count - 1)) / count
        Repeater {
            model: meter.visible ? Math.max(0, meter.count) : 0
            Rectangle {
                readonly property real pos: (index + 1) / meter.count
                width: meter.pill; height: 4; radius: 2
                color: (index + 0.5) / meter.count > s.level ? Theme.border
                     : s.dimmed ? Theme.off
                     : pos > 0.95 ? Theme.danger : pos > 0.8 ? Theme.caution : Theme.ok
            }
        }
    }
    MouseArea {
        visible: !s.readOnly   // not just disabled: a disabled MouseArea still sets the hand cursor
        cursorShape: Qt.PointingHandCursor
        id: area
        anchors.fill: parent
        function setV(mx) { s.dragValue = Math.max(0, Math.min(1, mx / track.width)); s.moved(s.dragValue) }
        onPressed: mouse => setV(mouse.x)
        onPositionChanged: mouse => { if (pressed) setV(mouse.x) }
        onReleased: s.dragValue = -1
    }
}
