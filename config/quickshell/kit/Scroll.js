.pragma library
// Touchpad scrolling's arithmetic, the macOS way (#3411): TouchScroll.qml feeds it the touchpad's pixel distances and
// moves the view. Pure functions over plain numbers, so scroll_test.py can check them, and every tunable value in
// TUNING below. On Linux libinput sends only raw distances: the acceleration and the glide after the fingers lift are
// the toolkit's job (GTK and Firefox do their own), so they are ours here.
//
// The model, from WebKit's ScrollingAccelerationCurve and MomentumEventDispatcher (macOS's own curve and glide):
// - Slow fingers move the content by their own distance (× touchScale), pixel for pixel, so it can be placed exactly.
// - Faster fingers get a gain that rises smoothly from 1 (accelFrom) to accelMax (accelFull): a quick swipe goes far.
// - After the fingers lift, the content glides on at the swipe's last speed and slows by a constant friction per 8 ms,
//   as WebKit's 0.975 (weaker swipes stop sooner, its 0.91 at a standstill), until it is slower than stopSpeed.
// - Fingers back on the touchpad stop it: the next swipe's first event (Wayland sends nothing for resting fingers).
//   A new swipe the same way while it glides adds its speed on, so repeated flicks build up (carry).

var TUNING = {
    touchScale: 0.8,     // content px per touchpad px at slow speed (Hyprland's scroll_factor 1.0; hypr/scroll.lua)
    step: 52,            // px per wheel notch when the touchpad sends no pixel distance
    accelFrom: 300,      // finger speed (touchpad px/s, × touchScale) below which nothing is added
    accelFull: 2400,     // finger speed at which the gain reaches accelMax
    accelMax: 2.6,       // the gain's ceiling
    speedWindow: 50,     // ms of events the finger speed is read from
    releaseWindow: 100,  // ms of events the glide's speed is read from
    liftGap: 60,         // ms: fingers that stopped this long before lifting don't glide
    swipeGap: 150,       // ms without events that start a new swipe
    friction: 0.975,     // the glide's speed kept per 8 ms (WebKit's trackpad value: a time constant of ~0.32 s)
    slowFriction: 0.91,  // the same for a glide slower than weakBelow, so a nudge settles quickly
    weakBelow: 250,      // px/s
    minGlide: 150,       // px/s: a slower lift doesn't glide
    stopSpeed: 30,       // px/s: the glide ends below this (half a pixel a frame at 60 Hz)
    maxSpeed: 12000      // px/s: the glide's ceiling
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// The gain for a finger speed (px/s, sign ignored): 1 below accelFrom, accelMax from accelFull, a smoothstep between
// so the change can't be felt as a step.
function gain(speed, t) {
    t = t || TUNING
    const x = clamp((Math.abs(speed) - t.accelFrom) / (t.accelFull - t.accelFrom), 0, 1)
    return 1 + (t.accelMax - 1) * x * x * (3 - 2 * x)
}

// Speed (px/s) of the samples [[time ms, distance], ...] within the last `window` ms before `now`. The span is at
// least 16 ms, so a single event isn't read as an infinitely fast one.
function speedOf(samples, now, window) {
    let sum = 0, first = now
    for (const s of samples) {
        if (now - s[0] > window) continue
        sum += s[1]
        first = Math.min(first, s[0])
    }
    return sum / Math.max(now - first, 16) * 1000
}

// One event of a swipe: the content distance for a touchpad distance `raw` (already × touchScale), with the gain of
// the finger's speed over the last speedWindow (this event included).
function track(rawSamples, now, raw, t) {
    t = t || TUNING
    const s = rawSamples.concat([[now, raw]])
    return raw * gain(speedOf(s, now, t.speedWindow), t)
}

// The glide's speed (px/s, + = content moves down) when the fingers lift at `now`: the content's speed over the last
// releaseWindow, none if they rested before lifting, plus `carry` (the glide this swipe interrupted) when the same way.
function release(samples, now, lastT, carry, t) {
    t = t || TUNING
    if (samples.length === 0 || now - lastT >= t.liftGap) return 0
    let v = speedOf(samples, now, t.releaseWindow)
    if (v !== 0 && Math.sign(v) === Math.sign(carry)) v += carry
    if (Math.abs(v) <= t.minGlide) return 0
    return clamp(v, -t.maxSpeed, t.maxSpeed)
}

// The glide's speed after dt seconds of friction. 0 once it is below stopSpeed, which ends the glide.
function decay(speed, dt, t) {
    t = t || TUNING
    const weak = Math.max(0, (t.weakBelow - Math.abs(speed)) / t.weakBelow)
    const alpha = t.friction - (t.friction - t.slowFriction) * weak
    const v = speed * Math.pow(alpha, dt / 0.008)
    return Math.abs(v) < t.stopSpeed ? 0 : v
}
