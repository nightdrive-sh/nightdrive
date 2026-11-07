// The rain of the rain face (RainFace.qml), without drawing it: a drop per column of cells, each with its own speed and
// trail length, starting again above the top after a random pause once it has fallen out; glyphs that flicker; and a
// glitch burst every 1.2–4.5 s. frame() gives every cell's glyph and colour index (0 none, 1…levels a trail from dim to
// bright, levels + 1 the head, levels + 2 and + 3 the glitch colours). Cells are row by row: index = row * cols + col.
import QtQuick

QtObject {
    id: rain
    property int cols: 1
    property int rows: 1
    property int levels: 64

    readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789:=*+<>|"

    function uniform(a, b) { return a + Math.random() * (b - a) }
    function randint(a, b) { return a + Math.floor(Math.random() * (b - a + 1)) }   // a…b, both included
    function glyph() { return glyphs[Math.floor(Math.random() * glyphs.length)] }
    function newTrail() { return randint(Math.max(6, Math.floor(rows / 4)), Math.max(10, Math.trunc(rows * 0.9))) }

    property var grid: []           // the glyph each cell has, shown when a trail passes over it
    property var head: []           // per column: the head's row (fractional, negative while above the top)
    property var speed: []          // rows a second
    property var trail: []          // rows
    property real glitchUntil: 0
    property real nextGlitch: 0
    property var bands: []          // the glitch's bands: { row, height, offset, colour }

    // A new rain whenever the size changes (a screen added, the scale changed)
    onColsChanged: reset()
    onRowsChanged: reset()
    Component.onCompleted: reset()
    function reset() {
        grid = Array.from({ length: cols * rows }, glyph)
        head = Array.from({ length: cols }, () => uniform(-rows * 2, rows))
        speed = Array.from({ length: cols }, () => uniform(8, 26))
        trail = Array.from({ length: cols }, newTrail)
        nextGlitch = Date.now() / 1000 + 2
        glitchUntil = 0; bands = []
    }
    function setGlyph(i) { grid[i] = glyph() }
    function glitching() { return Date.now() / 1000 < glitchUntil }

    function step(dt, now) {
        dt = Math.min(dt, 0.5)      // after a stall (the machine asleep) the drops don't all jump
        for (let x = 0; x < cols; x++) {
            head[x] += speed[x] * dt
            if (head[x] - trail[x] > rows) {        // fell out at the bottom: a new drop after a pause
                head[x] = uniform(-rows * 1.2, -2)
                speed[x] = uniform(8, 26)
                trail[x] = newTrail()
            }
            const y = Math.floor(head[x])        // the head is a new glyph every frame, left behind in its trail
            if (y >= 0 && y < rows) setGlyph(y * cols + x)
        }
        for (let i = Math.floor(cols * rows / 60); i > 0; i--) setGlyph(Math.floor(Math.random() * grid.length))
        if (now >= nextGlitch) {
            glitchUntil = now + uniform(0.08, 0.28)
            nextGlitch = now + uniform(1.2, 4.5)
            bands = Array.from({ length: randint(2, 5) }, () => ({
                row: Math.floor(Math.random() * rows), height: randint(1, Math.max(2, Math.floor(rows / 8))),
                offset: (Math.random() < 0.5 ? -1 : 1) * randint(2, Math.max(3, Math.floor(cols / 10))),
                colour: levels + 2 + Math.floor(Math.random() * 2) }))
        }
    }

    function frame() {
        const W = cols, H = rows, n = W * H
        const glyph = new Array(n).fill(" "), colour = new Array(n).fill(0)
        for (let x = 0; x < W; x++) {
            const hx = head[x], tl = trail[x]
            const y1 = Math.min(H - 1, Math.trunc(hx))
            for (let y = Math.max(0, Math.trunc(hx - tl)); y <= y1; y++) {
                const d = hx - y
                if (d < 0 || d >= tl) continue
                const i = y * W + x
                if (d < 1) colour[i] = levels + 1
                else colour[i] = 1 + Math.round(Math.pow(1 - d / tl, 1.6) * (levels - 1))
                glyph[i] = grid[i]
            }
        }
        if (glitching()) {
            for (const b of bands) {
                for (let y = b.row; y < Math.min(H, b.row + b.height); y++) {
                    const g = glyph.slice(y * W, y * W + W), c = colour.slice(y * W, y * W + W)
                    for (let x = 0; x < W; x++) {
                        const from = (((x - b.offset) % W) + W) % W, i = y * W + x
                        glyph[i] = g[from]
                        colour[i] = c[from] !== 0 && Math.random() < 0.55 ? b.colour : c[from]
                    }
                    for (let k = Math.floor(W / 12); k > 0; k--) {        // random bright glyphs
                        const i = y * W + Math.floor(Math.random() * W)
                        glyph[i] = rain.glyph(); colour[i] = b.colour
                    }
                }
            }
        }
        return { glyph: glyph, colour: colour }
    }
}
