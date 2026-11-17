// The server (protocol.md): the state as it streams in, requests, and the small helpers every part uses.

export const store = { state: null, online: false, listeners: [] };

export function subscribe(fn) { store.listeners.push(fn); }
function changed() { for (const fn of store.listeners) fn(store.state); }

// The state over Server-Sent Events. EventSource reconnects by itself; iOS drops the connection while the app is in
// the background, and it comes back on its own when the app does.
export function connect() {
  const es = new EventSource("/api/events");
  es.addEventListener("state", e => {
    try { store.state = JSON.parse(e.data); } catch { return; }
    store.online = true;
    changed();
  });
  es.onerror = () => { store.online = false; changed(); };
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && es.readyState === EventSource.CLOSED) connect();
  });
}

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

// A sheet over the page; returns it and a close function. A tap on the dark around it closes it.
export function sheet(html) {
  const scrim = document.createElement("div");
  scrim.className = "scrim";
  scrim.innerHTML = `<div class="sheet" role="dialog">${html}</div>`;
  const close = () => scrim.remove();
  scrim.addEventListener("pointerdown", e => { if (e.target === scrim) close(); });
  document.body.append(scrim);
  return { el: scrim.firstElementChild, close };
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
