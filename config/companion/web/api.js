// The server (protocol.md): the state as it streams in, requests, and the small helpers every part uses.

export const store = { state: null, online: false, listeners: [] };

// Returns its undo: a box that follows the state (question.js) stops when it closes
export function subscribe(fn) {
  store.listeners.push(fn);
  return () => { store.listeners = store.listeners.filter(f => f !== fn); };
}
function changed() { for (const fn of store.listeners) fn(store.state); }

// The state over Server-Sent Events. EventSource reconnects by itself only sometimes: it gives up for good when a
// retry gets an error (the server restarting behind tailscale serve), and on iOS a connection dropped while the app
// slept can stay open in name, silent, the tiles frozen as they were. So the server pings every 15 s, and a stream
// closed or silent for STALE_MS is opened again: checked every few seconds and as soon as the app is back in front.
const STALE_MS = 40000;
const CHECK_MS = 5000;
let es = null, heardAt = 0;

function heard() {
  heardAt = Date.now();
  if (!store.online) { store.online = true; changed(); }
}

export function connect() {
  es?.close();
  heardAt = Date.now();
  es = new EventSource("/api/events");
  es.addEventListener("state", e => {
    try { store.state = JSON.parse(e.data); } catch { return; }
    heardAt = Date.now();
    store.online = true;
    changed();
  });
  es.addEventListener("ping", heard);
  es.onerror = () => { store.online = false; changed(); };
}

function check() {
  if (!es || es.readyState === EventSource.CLOSED || Date.now() - heardAt > STALE_MS) connect();
}
setInterval(check, CHECK_MS);
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") check(); });
window.addEventListener("pageshow", check);
window.addEventListener("online", check);

export async function post(path, body) {
  try {
    const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Companion": "1" },
                                  body: body === undefined ? "" : JSON.stringify(body) });
    const answer = await r.json().catch(() => ({}));
    if (!r.ok) { toast(answer.error || `It didn't work (${r.status})`, true); return false; }
    return true;
  } catch {
    toast("No connection to the computer", true);
    return false;
  }
}

export async function get(path) {
  const r = await fetch(path);
  return r.json();
}

let toastTimer;
export function toast(text, bad = false) {
  let el = document.querySelector(".toast");
  if (!el) { el = document.createElement("div"); document.body.append(el); }
  el.className = "toast" + (bad ? " bad" : "");
  el.textContent = text;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 2600);
}

export function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

// A sheet over the page; returns it and a close function. A tap on the dark around it closes it: on its click, both
// ends on the dark, so the click doesn't fall through to the tile under it (closed on pointerdown, the New session
// tile got the click and opened the box again), and a press that starts in the sheet (holding its mic) never does.
// onClose runs however it closes; cls is the sheet's own class (small: a question's narrower box).
export function sheet(html, { onClose = () => {}, cls = "" } = {}) {
  const scrim = document.createElement("div");
  scrim.className = "scrim";
  scrim.innerHTML = `<div class="sheet ${cls}" role="dialog">${html}</div>`;
  const close = () => { if (scrim.isConnected) { scrim.remove(); onClose(); } };
  let downOnScrim = false;
  scrim.addEventListener("pointerdown", e => { downOnScrim = e.target === scrim; });
  scrim.addEventListener("click", e => { if (downOnScrim && e.target === scrim) close(); });
  document.body.append(scrim);
  return { el: scrim.firstElementChild, close };
}

// A yes-or-no question in a sheet of the page's own, not the browser's confirm() (which looks like another app's and
// names the web address): true for yes, false for Cancel or a tap outside. danger: the yes button in red.
export function ask(title, text, yes, danger = false) {
  return new Promise(resolve => {
    let answer = false;
    const s = sheet(`<div class="row"><span class="sec">${esc(title)}</span></div>
      <div class="ask-text">${esc(text)}</div>
      <div class="row"><span class="spacer"></span><button class="pill no">Cancel</button>
        <button class="pill main yes${danger ? " danger" : ""}">${esc(yes)}</button></div>`,
      { cls: "small", onClose: () => resolve(answer) });
    s.el.querySelector(".no").onclick = s.close;
    s.el.querySelector(".yes").onclick = () => { answer = true; s.close(); };
  });
}

// "12 min", "2 h 5 min" since an epoch second
export function since(epoch) {
  const m = Math.max(0, Math.round((Date.now() / 1000 - epoch) / 60));
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`;
}

// A press held for HOLD ms: onHold instead of onTap
export function press(el, onTap, onHold, hold = 550) {
  let timer = null, held = false;
  el.addEventListener("pointerdown", () => { held = false; timer = setTimeout(() => { held = true; onHold(); }, hold); });
  const end = () => clearTimeout(timer);
  el.addEventListener("pointerup", () => { end(); if (!held) onTap(); });
  el.addEventListener("pointerleave", end);
  el.addEventListener("pointercancel", end);
  el.addEventListener("contextmenu", e => e.preventDefault());
}
