// The rain screensaver's face: columns of falling half-width katakana and digits in violet, each drop a bright head and a
// fading trail, glyphs flickering, and now and then a glitch: a few bands of rows shifted sideways in pink or cyan.
// Drawn as a terminal's character cells (it began as one, in kitty: JetBrains Mono at 18 pt), in the same colours.
// Used by the screensaver (../SaverShell.qml, one per screen) and by the lock (greeter/LockSaver.qml loads this file).
// Opaque. The rain itself is RainState.qml. A frame is drawn by one shader (rain.frag) from a small image of the cells
// (a Canvas, two pixels a cell) and an atlas of the glyphs made once: ~18 % of a core in the sandbox, against ~21 % for
// kitty and Python. A Text per cell was most of a core, as the scene graph rebuilt its batches over 3000 text nodes
// whenever a few changed.
import QtQuick

Rectangle {
    id: face
    clip: true
    color: rgb(bg)
    readonly property int fps: 24

    readonly property var bg: [9, 2, 20]
    readonly property var head: [255, 215, 255]
    readonly property var trailTop: [220, 70, 255]
    readonly property var trailBottom: [45, 8, 95]
    readonly property var glitchColours: [[255, 60, 200], [80, 230, 255]]
    readonly property int levels: 64            // a trail's brightness, in steps

    // A terminal cell (kitty's font_size 18: 24 px), whole device pixels as a terminal's are: the atlas then maps onto
    // the screen pixel for pixel
    readonly property real dpr: Window.window ? Window.window.devicePixelRatio : 1
    FontMetrics { id: fm; font { family: "JetBrains Mono"; weight: Font.Thin; pixelSize: 24 } }
    // (fm.font is read first: a method call isn't a binding dependency)
    readonly property real cw: Math.max(1, Math.round((fm.font.family && fm.advanceWidth("M")) * dpr)) / dpr
    readonly property real ch: Math.max(1, Math.round(fm.height * dpr)) / dpr
    readonly property int cols: Math.ceil(width / cw)
    readonly property int rows: Math.ceil(height / ch)

    function lerp(a, b, t) { return [0, 1, 2].map(i => Math.trunc(a[i] + (b[i] - a[i]) * t)) }
    function rgb(c) { return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, 1) }
    // By colour index (RainState.frame()), as [r, g, b]: none, the trail from dim to bright, the head, the glitch colours
    readonly property var colours: {
        const p = [bg]
        for (let i = 0; i < levels; i++) {
            const b = i / (levels - 1)
            p.push(lerp(bg, lerp(trailBottom, trailTop, b), Math.min(1, 0.25 + b * 1.2)))
        }
        return p.concat([head], glitchColours)
    }

    RainState { id: rain; cols: face.cols; rows: face.rows; levels: face.levels }
    // A glyph's number in the atlas, 1…
    readonly property var glyphNumber: {
        const m = {}
        for (let i = 0; i < rain.glyphs.length; i++) m[rain.glyphs[i]] = i + 1
        return m
    }

    // The atlas: every glyph once, in white, a cell apart; drawn into a texture once, never on screen
    Row {
        id: atlas
        Repeater {
            model: rain.glyphs.length
            Text {
                required property int index
                width: face.cw; height: face.ch
                text: rain.glyphs[index]
                color: "white"
                font: fm.font
            }
        }
    }
    ShaderEffectSource { id: atlasTexture; sourceItem: atlas; hideSource: true; smooth: false }

    // The cells: per cell its colour, then its glyph's number in the atlas (1…, 0 none) in red. Only the cells with a
    // glyph are drawn, on a background of empty cells: fillRect is a call per rectangle, where ImageData's writes were a
    // call per byte (all of a core)
    readonly property var colourStyle: colours.map(c => `rgb(${c[0]},${c[1]},${c[2]})`)
    readonly property var numberStyle: Array.from({ length: rain.glyphs.length + 1 }, (_, i) => `rgb(${i},0,0)`)
    Canvas {
        id: data
        width: face.cols * 2; height: face.rows
        renderStrategy: Canvas.Immediate
        smooth: false
        property var frame: null
        onPaint: {
            const ctx = getContext("2d")
            ctx.fillStyle = "#000000"
            ctx.fillRect(0, 0, width, height)
            if (!frame) return
            const W = face.cols, n = W * face.rows, number = face.glyphNumber
            for (let i = 0; i < n; i++) {
                const c = frame.colour[i]
                if (c === 0) continue
                const x = (i % W) * 2, y = Math.floor(i / W)
                ctx.fillStyle = face.colourStyle[c]; ctx.fillRect(x, y, 1, 1)
                ctx.fillStyle = face.numberStyle[number[frame.glyph[i]] || 0]; ctx.fillRect(x + 1, y, 1, 1)
            }
        }
    }

    ShaderEffect {
        anchors.fill: parent
        // Through a ShaderEffectSource, which also keeps the Canvas off the screen (an invisible one doesn't paint)
        property variant cells: ShaderEffectSource { sourceItem: data; hideSource: true; smooth: false }
        property variant atlas: atlasTexture
        property size grid: Qt.size(face.cols, face.rows)
        property size cell: Qt.size(face.cw, face.ch)
        property size area: Qt.size(width, height)
        property real glyphCount: rain.glyphs.length
        property color bg: face.color
        fragmentShader: Qt.resolvedUrl("rain.frag.qsb")
    }

    property real last: Date.now()
    Timer {
        interval: 1000 / face.fps; running: true; repeat: true
        onTriggered: {
            const now = Date.now()
            rain.step((now - face.last) / 1000, now / 1000)
            face.last = now
            data.frame = rain.frame()
            data.requestPaint()
        }
    }
}
