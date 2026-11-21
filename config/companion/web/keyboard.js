// The on-screen keyboard and the session view (#3370). iOS (Safari, the app's WKWebView) lays the keyboard over the
// page without making it smaller: a fixed view's bottom, with the field to write in, went under the keyboard. The
// visual viewport is the part that shows, so the view takes its height and place (--vh, --vtop on the root, read by
// app.css), and the field sits on the keyboard with the conversation's end above it. html gets the class kb while
// the keyboard is up (the view's buttons make way for the conversation on a phone, app.css).
// Where the browser makes the page smaller itself (Android, a desktop), the visual viewport is the page: nothing moves.
const vv = window.visualViewport;
const KB_PX = 120;         // the visual viewport this much lower than the window: a keyboard, not a toolbar

const listeners = [];
// fn(before) after the view's size changed; before: what it was
export function onViewport(fn) { listeners.push(fn); }

function update() {
  if (!vv) return;
  const root = document.documentElement.style;
  const before = root.getPropertyValue("--vh");
  root.setProperty("--vh", `${Math.round(vv.height)}px`);
  root.setProperty("--vtop", `${Math.round(vv.offsetTop)}px`);
  document.documentElement.classList.toggle("kb", innerHeight - vv.height > KB_PX);
  if (before !== root.getPropertyValue("--vh")) for (const fn of listeners) fn(before);
}

if (vv) {
  vv.addEventListener("resize", update);
  // iOS scrolls the page to show a focused field even when it shows already: the view follows where it went
  vv.addEventListener("scroll", update);
  update();
}
