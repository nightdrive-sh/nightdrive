import QtQuick
import "kit/Scroll.js" as Scroll

// Touchpad scrolling for a Flickable (ListView, GridView): put it inside the view. Qt's own touchpad scrolling is slow
// and stops dead when the fingers lift. This one follows the fingers pixel for pixel when they move slowly, goes
// further for a quick swipe, glides on after they lift and stops when they touch again, as macOS does: the arithmetic
// and every tunable value are in kit/Scroll.js (TUNING). A mouse wheel keeps Qt's own scrolling.
// Every app links this file (plugins/<app>/app/TouchScroll.qml), so "kit/Scroll.js" is found through its kit link.
// The glide is our own (Flickable.flick() is ignored when a swipe interrupted the previous glide).
WheelHandler {
    id: h
    required property Flickable view
    property real step: Scroll.TUNING.step   // px per wheel notch when the touchpad sends no pixel distance (a row)
    property var samples: []        // [time ms, content dy] of the current swipe, the last releaseWindow
    property var raw: []            // [time ms, touchpad dy × touchScale]: the finger's speed, for the gain
    property double lastT: 0
    property real carry: 0          // the glide's speed when this swipe started (px/s, + = content moves down)
    property real speed: 0          // the glide's current speed
    property real setY: 0           // the contentY we set last: anything else (keys, hover) stops the glide
    target: null
    acceptedDevices: PointerDevice.TouchPad

    // Scrolls by dy (+ = towards the top); false when it hit either end. The ends take the view's own margins in, so
    // a list with a topMargin (Deck's under its title bar's line) comes back to its gap instead of stopping at the line.
    function scrollBy(dy) {
        const min = view.originY - view.topMargin
        const max = Math.max(min, view.originY + view.contentHeight + view.bottomMargin - view.height)
        const want = view.contentY - dy
        const y = Math.max(min, Math.min(max, want))
        view.contentY = y
        setY = y
        return y === want
    }

    function stop() { glide.stop(); speed = 0 }

    property FrameAnimation glide: FrameAnimation {
        onTriggered: {
            if (Math.abs(h.view.contentY - h.setY) > 0.5) { h.stop(); return }
            const dt = Math.min(frameTime, 0.05)
            h.speed = Scroll.decay(h.speed, dt)
            if (h.speed === 0 || !h.scrollBy(h.speed * dt)) h.stop()
        }
    }

    // A press in the view (on its ground; a row's own MouseArea keeps it) stops the glide, as a touch does on a Mac.
    // Passive: the press still reaches whatever is under it.
    property TapHandler press: TapHandler {
        parent: h.view
        gesturePolicy: TapHandler.DragThreshold
        onPressedChanged: if (pressed) h.stop()
    }

    onWheel: e => {
        const t = Scroll.TUNING
        const now = Date.now()
        if (e.phase === Qt.ScrollEnd) {
            const v = Scroll.release(samples, now, lastT, carry)
            samples = []; raw = []; carry = 0
            if (v !== 0) {
                speed = v
                setY = view.contentY
                glide.start()
            }
            return
        }
        if (samples.length === 0 || now - lastT > t.swipeGap) {      // a new swipe: catch the glide
            carry = glide.running ? speed : 0
            samples = []; raw = []
        }
        stop()
        view.cancelFlick()
        let dy
        if (e.pixelDelta.y !== 0) {
            const r = e.pixelDelta.y * t.touchScale
            dy = Scroll.track(raw, now, r)
            raw = raw.filter(s => now - s[0] <= t.speedWindow).concat([[now, r]])
        } else {
            dy = e.angleDelta.y / 120 * step
        }
        scrollBy(dy)
        lastT = now
        samples = samples.filter(s => now - s[0] <= t.releaseWindow).concat([[now, dy]])
    }
}
