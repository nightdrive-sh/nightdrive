// Back with a swipe from the left edge, as an iPhone app has it: the session's view (detail.js) follows the finger and
// goes to the list when let go past the middle or flicked; short of that it slides back. Made here because Safari's own
// edge gesture does nothing in the app added to the home screen; in a Safari tab (navigator.standalone false) the
// page leaves the edge to Safari, whose gesture goes back in the history (detail.js pushes a step for the view).
// It stays out of the way of the rest: only a press that starts at the edge, moves sideways before it moves down or
// up (the log scrolls), and moves soon (a held press selects text) counts; one on a button (Answer held) never does.
const EDGE_PX = 12;          // a press in the view's left padding (16 px, or the safe area's) or this far past it
const DECIDE_PX = 10;        // moved this far, it is a swipe (sideways) or not (down or up)
const HOLD_MS = 400;         // still before this long: a hold, not a swipe (the text's selection is iOS's)
const FLICK = 0.5;           // px/ms to the right at let go: a flick, back however far it came
const FLICK_MIN_PX = 40;     // ... once it has come this far
const SLIDE_MS = 220;
const SKIP = "button, a, input, textarea, select, [contenteditable]";

export const swipeOn = navigator.standalone !== false;

// el slides; back() runs once it has gone (the caller closes the view)
export function edgeSwipe(el, back) {
  if (!swipeOn) return;
  let t = null;    // { x, y, at, on, pts: [[x, at]] } while a press is followed
  const move = x => { el.style.transform = x ? `translateX(${x}px)` : ""; };
  const slide = (x, then) => {
    el.style.transition = `transform ${SLIDE_MS}ms cubic-bezier(.2, .7, .3, 1)`;
    move(x);
    setTimeout(() => { el.style.transition = ""; el.classList.remove("swiping"); then?.(); }, SLIDE_MS);
  };
  el.addEventListener("touchstart", e => {
    t = null;
    if (e.touches.length !== 1 || el.style.transition) return;
    const p = e.touches[0];
    if (p.clientX > parseFloat(getComputedStyle(el).paddingLeft) + EDGE_PX || e.target.closest(SKIP)) return;
    t = { x: p.clientX, y: p.clientY, at: e.timeStamp, on: false, pts: [] };
  }, { passive: true });
  el.addEventListener("touchmove", e => {
    if (!t) return;
    const p = e.touches[0], dx = p.clientX - t.x, dy = p.clientY - t.y;
    if (!t.on) {
      if (Math.hypot(dx, dy) < DECIDE_PX) return;
      const selected = !!getSelection()?.toString();
      if (dx <= Math.abs(dy) || e.timeStamp - t.at > HOLD_MS || selected) { t = null; return; }
      t.on = true;
      el.classList.add("swiping");
    }
    e.preventDefault();       // not the log's scroll under it, nor a selection
    t.pts.push([p.clientX, e.timeStamp]);
    if (t.pts.length > 5) t.pts.shift();
    move(Math.max(0, dx));
  }, { passive: false });
  const end = e => {
    const s = t;
    t = null;
    if (!s?.on) return;
    const x = (s.pts.at(-1)?.[0] ?? s.x) - s.x;
    const [x0, t0] = s.pts[0] || [s.x, s.at];
    const v = (s.pts.at(-1)?.[0] - x0) / Math.max(1, (s.pts.at(-1)?.[1] ?? t0) - t0);
    const away = e.type === "touchend" && (x > el.clientWidth / 2 || (v > FLICK && x > FLICK_MIN_PX));
    if (away) slide(el.clientWidth, back); else slide(0);
  };
  el.addEventListener("touchend", end);
  el.addEventListener("touchcancel", end);
}
