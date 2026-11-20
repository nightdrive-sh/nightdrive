// Words sent to a session that its log doesn't have yet (#3139). The log is read every 2 s and Claude Code writes a
// prompt only once it took it, so without these your own words came seconds after you let go. Each shows at once at
// the end of the session's view, faded, until a prompt with the same words turns up in the log after where the log
// ended when they went; then the log's own line is the one shown, never both.
// They didn't get there when the request failed, or when the log still lacks them GRACE_MS after they went and the
// session was last at work: a prompt given mid-turn is written only when Claude reads it in, with its next tool
// result, so while the session works they are waiting, not lost. Not there, they stay in sight with Send again.
import { get, subscribe } from "./api.js";

const GRACE_MS = 20000;
const ANCHOR = 3;          // the log's last lines kept as where it ended when the words went
const SAME = 300;          // characters compared: the log keeps a long prompt cut, the paste drops control codes

const sent = new Map();    // session id → [{ key, text, at, anchor, sending, failed }], oldest first
const busyAt = new Map();  // session id → when it was last seen at work
const listeners = [];
let next = 0;

export function onPending(fn) { listeners.push(fn); }
function changed(id) { for (const fn of listeners) fn(id); }

const norm = s => String(s ?? "").replace(/[\x00-\x1f\x7f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, SAME);
const same = (a, b) => a.role === b.role && a.kind === b.kind && a.text === b.text;

export function pending(id) { return sent.get(id) || []; }

// Before the words go: where the log ends now. Read before the request, so the words can't be in it yet.
async function anchorOf(id) {
  try {
    const log = await get(`/api/sessions/${encodeURIComponent(id)}/log`);
    return Array.isArray(log) ? log.slice(-ANCHOR).map(({ role, kind, text }) => ({ role, kind, text })) : null;
  } catch { return null; }
}

// Sends words with deliver() (a promise of true when the request went) and keeps them until the log has them.
// Sending the same words again takes the place of ones that didn't get there.
export async function track(id, text, deliver) {
  const list = (sent.get(id) || []).filter(p => !(p.failed && norm(p.text) === norm(text)));
  const p = { key: `p${++next}`, text, at: Date.now(), anchor: null, sending: true, failed: false };
  list.push(p);
  sent.set(id, list);
  changed(id);
  p.anchor = await anchorOf(id);
  const ok = await deliver();
  p.sending = false;
  if (!ok) { p.failed = true; changed(id); }
  return ok;
}

// The first place in log after the anchor (its lines in a row); 0 when it isn't there (moved out of the log's window,
// or not known): then any matching prompt counts
function after(log, anchor) {
  if (!anchor?.length) return 0;
  for (let i = 0; i + anchor.length <= log.length; i++) {
    if (anchor.every((a, j) => same(a, log[i + j]))) return i + anchor.length;
  }
  return 0;
}

// The view's log came: what it has is no longer pending, what it lacks too long didn't get there. True when changed.
export function reconcile(id, log) {
  const list = sent.get(id);
  if (!list?.length || !Array.isArray(log)) return false;
  const now = Date.now(), quiet = now - (busyAt.get(id) || 0);
  let from = 0, change = false;
  const keep = [];
  for (const p of list) {
    if (p.sending) { keep.push(p); continue; }        // its request hasn't come back: the log can't have it yet
    const start = Math.max(from, after(log, p.anchor));
    const want = norm(p.text);
    const i = log.findIndex((e, k) => k >= start && e.role === "user" && e.kind === "text" && norm(e.text) === want);
    if (i >= 0) { from = i + 1; change = true; continue; }        // the log's own line shows it now
    if (!p.failed && now - p.at > GRACE_MS && quiet > GRACE_MS) { p.failed = true; change = true; }
    keep.push(p);
  }
  if (keep.length) sent.set(id, keep); else sent.delete(id);
  return change;
}

export function forget(id, key) {
  const list = (sent.get(id) || []).filter(p => p.key !== key);
  if (list.length) sent.set(id, list); else sent.delete(id);
  changed(id);
}

// While it works (or waits on a permission) words given mid-turn wait to be read in
subscribe(state => {
  for (const s of state?.sessions || []) {
    if (s.state === "working" || s.state === "permission") busyAt.set(s.id, Date.now());
  }
});
