// The synthwave screensaver's face: a sky from deep violet to magenta, twinkling stars drifting right, a striped sun on a
// slow arc from left to right, and a mountain ridge scrolling past. Drawn as a terminal's character cells (it began as
// one, in kitty: cells the size of JetBrains Mono at 9 pt), so everything moves a whole cell at a time.
// Used by the screensaver (../SaverShell.qml, one per screen) and by the lock (greeter/LockSaver.qml loads this file).
// Opaque. Scene-graph rectangles and text, not a Canvas: the GPU draws them, and only what changed is updated.
import QtQuick

Item {
    id: face
    clip: true
    readonly property int fps: 20
    readonly property real day: 240            // s from sunrise to sunset
    readonly property int starCount: 140

    readonly property var skyTop: [12, 4, 32]
    readonly property var skyMid: [58, 12, 96]
    readonly property var skyLow: [150, 30, 140]
    readonly property var mountain: [28, 8, 58]
    readonly property var mountainEdge: [190, 70, 255]
    readonly property var sunTop: [255, 230, 90]
    readonly property var sunBottom: [255, 40, 150]
    readonly property var starLight: [255, 220, 255]

    // A terminal cell (kitty's font_size 9: 12 px). Normal, not kitty's Thin: kitty draws thin text heavier
    FontMetrics { id: fm; font { family: "JetBrains Mono"; weight: Font.Normal; pixelSize: 12 } }
    // (fm.font is read first: a method call isn't a binding dependency)
    readonly property real cw: Math.max(1, fm.font.family && fm.advanceWidth("M"))
    readonly property real ch: Math.max(1, fm.height)
    readonly property int cols: Math.ceil(width / cw)
    readonly property int rows: Math.ceil(height / ch)   // the horizon is the bottom: the sky fills the screen

    function lerp(a, b, t) { return [0, 1, 2].map(i => Math.trunc(a[i] + (b[i] - a[i]) * t)) }
    function mix(c, f) { return c.map(v => Math.min(255, Math.trunc(v * f))) }
    function rgb(c) { return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, 1) }

    // Seconds since it started, a frame at a time
    property real t: 0
    property real started: Date.now()
    Timer { interval: 1000 / face.fps; running: true; repeat: true; onTriggered: face.t = (Date.now() - face.started) / 1000 }

    // The same sky every time: a seeded random (mulberry32)
    function seeded(seed) {
        return () => {
            seed = (seed + 0x6D2B79F5) | 0
            let r = Math.imul(seed ^ (seed >>> 15), 1 | seed)
            r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r
            return ((r ^ (r >>> 14)) >>> 0) / 4294967296
        }
    }
    readonly property var stars: {
        const rnd = seeded(84), glyphs = "·.+*"
        return Array.from({ length: starCount }, () => ({ x: rnd(), y: Math.pow(rnd(), 1.3), phase: rnd() * 6.28,
                                                           glyph: glyphs[Math.floor(rnd() * glyphs.length)] }))
    }

    // Sky: a colour per row of cells, magenta at the bottom
    Column {
        Repeater {
            model: face.rows
            Rectangle {
                required property int index
                width: face.width; height: face.ch
                color: {
                    const f = index / Math.max(1, face.rows - 1)
                    return face.rgb(f < 0.625 ? face.lerp(face.skyTop, face.skyMid, f * 1.6)
                                              : face.lerp(face.skyMid, face.skyLow, (f - 0.625) / 0.375))
                }
            }
        }
    }

    // Stars: each twinkles on its own beat and is hidden at its dimmest; all drift right a cell every 2.5 s
    Repeater {
        model: face.stars
        Text {
            required property var modelData
            readonly property real tw: 0.5 + 0.5 * Math.sin(face.t * 1.7 + modelData.phase)
            x: (Math.trunc(modelData.x * face.cols + face.t * 0.4) % face.cols) * face.cw
            y: Math.trunc(modelData.y * face.rows * 0.8) * face.ch
            visible: tw > 0.25
            text: modelData.glyph
            color: face.rgb(face.mix(face.starLight, 0.35 + tw * 0.65))
            font: fm.font
        }
    }

    Sun {
        cw: face.cw; ch: face.ch; cols: face.cols; rows: face.rows; t: face.t; day: face.day
        topColor: face.sunTop; bottomColor: face.sunBottom
    }

    Mountains {
        cw: face.cw; ch: face.ch; cols: face.cols; rows: face.rows; t: face.t
        body: face.rgb(face.mountain); edge: face.rgb(face.mountainEdge)
    }
}
