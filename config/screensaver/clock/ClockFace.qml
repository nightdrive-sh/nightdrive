// The clock screensaver's face: a big theme-coloured HH:MM:SS. On a change the old digit slides up and out while the new
// one comes up from below in step with it, with a small spring at the end. Transparent: the caller draws the black.
// Used by the screensaver (../SaverShell.qml, one per screen) and by the lock (greeter/LockSaver.qml loads this file).
// It redraws only while a digit slides, ~0.6 s a second.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: face
    readonly property int slideMs: 600         // one digit's slide
    readonly property real overshoot: 1.3      // the spring: how far past its place a digit goes before settling (OutBack)
    readonly property string fontFace: "Six Caps"  // Google Fonts (OFL), installed by install.sh into ~/.local/share/fonts
    readonly property int weight: Font.Normal  // Six Caps has one weight
    readonly property real fill: 0.8           // the clock's share of the width (capped by the height)
    readonly property real shade: 0.5          // the theme colour darkened to this: a saver shouldn't light up the room
    readonly property real gap: 0.32           // space between digits, in digit widths (the font's own spacing is too loose)

    // Theme colours: neither the saver nor the lock can import ../quickshell, so this reads the file Theme.qml reads
    property var c: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.cache/nightdrive/theme.json"
        onLoaded: { try { face.c = JSON.parse(text()) } catch (e) {} }
    }
    readonly property color base: c.primary || "#c071eb"   // the clock in the theme's main colour, darkened
    readonly property color ink: Qt.rgba(base.r * shade, base.g * shade, base.b * shade, 1)

    property date now: new Date()
    Timer { interval: 1000 - new Date().getMilliseconds(); running: true; repeat: true
            onTriggered: { face.now = new Date(); interval = 1000 - face.now.getMilliseconds() } }

    // The font at 100 px, measured by its ink: every digit cell is as wide as the widest digit plus the gap, so a
    // proportional font doesn't jitter
    FontMetrics { id: fm; font { family: face.fontFace; weight: face.weight; pixelSize: 100 } }
    // (fm.font is read first: a method call isn't a binding dependency, and these would keep the default font's sizes)
    readonly property real inkW: fm.font.family && Math.max(...("0123456789".split("").map(ch => fm.tightBoundingRect(ch).width))) / 100
    readonly property real digitW: inkW * (1 + gap)
    readonly property real colonW: fm.font.family && fm.tightBoundingRect(":").width / 100 + inkW * gap
    readonly property real digitH: fm.font.family && fm.tightBoundingRect("0").height / 100

    // HH:MM:SS, all the same size: six digits and two colons across `fill` of the width, digits at most 55 % of the height
    readonly property real size: Math.min(width * fill / (6 * digitW + 2 * colonW), height * 0.55 / digitH)

    // One digit in its own clipped cell. Both glyphs ride the same progress: the old one goes up exactly as the new one comes in
    component Digit: Item {
        id: d
        property string value: "0"
        property real size: 100
        property string shown: value
        property string previous: value
        property real p: 1                      // 0 → 1 over a change
        width: face.digitW * size
        height: face.digitH * size * 1.04       // clipped to the digits' own band: they appear and vanish at its edges
        clip: true
        readonly property real lift: (fm.ascent / 100 - face.digitH * 1.02) * size   // the font's empty space above the digits
        onValueChanged: { previous = shown; shown = value; anim.restart() }
        NumberAnimation { id: anim; target: d; property: "p"; from: 0; to: 1; duration: face.slideMs
                          easing.type: Easing.OutBack; easing.overshoot: face.overshoot }
        Text {
            text: d.previous; font: cur.font; color: face.ink; renderType: cur.renderType
            anchors.horizontalCenter: parent.horizontalCenter
            y: -d.lift - d.height * d.p
            visible: d.p < 1
        }
        Text {
            id: cur
            text: d.shown; color: face.ink
            renderType: Text.CurveRendering    // the default distance-field glyphs turn polygonal at this size
            font { family: face.fontFace; weight: face.weight; pixelSize: d.size }
            anchors.horizontalCenter: parent.horizontalCenter
            y: -d.lift + d.height * (1 - d.p)
        }
    }

    component Pair: Row {
        property string value: "00"
        property real size: 100
        Digit { value: parent.value[0]; size: parent.size }
        Digit { value: parent.value[1]; size: parent.size }
    }

    component Colon: Item {
        property real size: 100
        width: face.colonW * size; height: face.digitH * size * 1.04
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: -(fm.ascent / 100 - face.digitH * 1.02) * parent.size
               text: ":"; color: face.ink; renderType: Text.CurveRendering
               font { family: face.fontFace; weight: face.weight; pixelSize: parent.size } }
    }

    Row {
        anchors.centerIn: parent
        Pair { value: Qt.formatTime(face.now, "HH"); size: face.size }
        Colon { size: face.size }
        Pair { value: Qt.formatTime(face.now, "mm"); size: face.size }
        Colon { size: face.size }
        Pair { value: Qt.formatTime(face.now, "ss"); size: face.size }
    }
}
