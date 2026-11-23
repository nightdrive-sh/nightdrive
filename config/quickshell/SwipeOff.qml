import QtQuick

// A two-finger swipe left or right that takes its parent away (Dashboard #3118: a reminder's banner). The same feel as
// a notification card's swipe (NotificationCard.qml), but either way: the item follows the fingers, goes once it's
// past `distance` (or on a fast flick), carrying on at the swipe's speed, else springs back. Up and down don't move it
// (Jari's call: tried, it felt awkward). This only counts: the item binds its offset and fade to dx and fade, and is
// removed on gone().
//   Item { id: row; transform: Translate { x: sw.dx }; opacity: 1 - sw.fade; SwipeOff { id: sw; onGone: … } }
WheelHandler {
    id: swipe
    signal gone()

    // --- Tunables (as NotificationCard's) ---
    property real touchScale: 0.8          // the same as kit/Scroll.js TUNING.touchScale
    property real distance: 60             // px either way
    property real fadeOver: 240            // px: fully faded this far
    property real flickSpeed: 900          // px/s on release
    property real direction: -1            // natural_scroll = false: fingers to the right give a negative delta
    property real minOutSpeed: 400         // px/s: the slowest start when it goes
    property real outAccel: 6000           // px/s²: then it speeds up
    property real outTo: 600               // px: gone once this far

    property real dx: 0
    readonly property real fade: Math.min(1, Math.abs(dx) / fadeOver)

    property var samples: []               // [time ms, dx] of the last 100 ms
    property double lastT: 0
    target: null
    acceptedDevices: PointerDevice.TouchPad
    orientation: Qt.Horizontal

    // The swipe's speed (px/s, signed) at its last event; fingers that stopped before lifting give 0
    function speedNow() {
        if (samples.length === 0 || Date.now() - lastT > 60) return 0
        const span = Math.max(lastT - samples[0][0], 16)
        return samples.reduce((a, s) => a + s[1], 0) / span * 1000
    }
    function release() {
        const v = speedNow()
        samples = []
        // A flick goes the way it was flicked, if the item has moved that way
        if (Math.abs(v) > flickSpeed && dx * v > 0) leave(v)
        else back.start()
    }
    function leave(v) {
        idle.stop()
        samples = []
        out.way = dx < 0 ? -1 : 1
        out.speed = Math.max(Math.abs(v), minOutSpeed)
        out.start()
    }

    onWheel: e => {
        if (out.running) return
        if (e.phase === Qt.ScrollEnd) { idle.stop(); release(); return }
        const raw = e.pixelDelta.x !== 0 ? e.pixelDelta.x * touchScale : e.angleDelta.x / 120 * 52
        const mx = raw * direction
        if (mx === 0) return
        back.stop()
        dx += mx
        const now = Date.now()
        samples = samples.filter(s => now - s[0] <= 100).concat([[now, mx]])
        lastT = now
        if (Math.abs(dx) > distance) { leave(speedNow()); return }
        idle.restart()                     // in case no ScrollEnd arrives: a pause counts as a release
    }

    property Timer idle: Timer { interval: 100; onTriggered: swipe.release() }
    // Leaves at the swipe's own speed, so it doesn't hitch when the fingers lift
    property FrameAnimation out: FrameAnimation {
        property real speed: 0
        property int way: 1
        onTriggered: {
            const dt = Math.min(frameTime, 0.05)
            speed += swipe.outAccel * dt
            swipe.dx += way * speed * dt
            if (Math.abs(swipe.dx) >= swipe.outTo) { stop(); swipe.gone() }
        }
    }
    property NumberAnimation back: NumberAnimation { target: swipe; property: "dx"; to: 0; duration: 220; easing.type: Easing.OutBack }
}
