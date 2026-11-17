// A session's own view, over the whole screen: what it said and did lately (GET /api/sessions/ID/log: your prompts,
// Claude's texts, its tool calls), read again every REFRESH_MS while it is open, and the session's buttons below it.
// A tap on a tile opens it; × or Esc closes it. It stays at the end as new lines come, unless you scrolled up to read.
import { esc, get, since, store, subscribe } from "./api.js";
import { icon } from "./icons.js";
import { act, ASKS } from "./act.js";
import { markdown } from "./markdown.js";

const REFRESH_MS = 2000;
const AT_END_PX = 40;      // this close to the bottom still counts as following along
let view = null;           // { id, el, timer, logSig, frameSig }

export function openDetail(id) {
  close();
  const el = document.createElement("div");
  el.className = "detail";
  el.setAttribute("role", "dialog");
  el.innerHTML = '<header class="dhead"></header><div class="log"></div><footer class="dfoot"></footer>';
  document.body.append(el);
  view = { id, el, timer: setInterval(load, REFRESH_MS), logSig: "", frameSig: "" };
  el.addEventListener("click", e => {
    if (e.target.closest(".close")) return close();
    const b = e.target.closest("button[data-act]");
    if (b) act(view.id, b.dataset.act, b).then(ok => { if (ok && b.dataset.act === "close") close(); });
  });
  frame(store.state);
  load();
}

function close() {
  if (!view) return;
  clearInterval(view.timer);
  view.el.remove();
  view = null;
}
document.addEventListener("keydown", e => { if (e.key === "Escape" && !document.querySelector(".scrim")) close(); });

// Claude's texts are Markdown; your prompts and the tool lines are shown as they are
function line(e) {
  if (e.kind === "tool") return `<div class="msg tool">${esc(e.text)}</div>`;
  if (e.role === "user") return `<div class="msg you">${esc(e.text)}</div>`;
  return `<div class="msg claude md">${markdown(e.text)}</div>`;
}

async function load() {
  if (!view) return;
  const id = view.id;
  let log;
  try { log = await get(`/api/sessions/${encodeURIComponent(id)}/log`); } catch { return; }
  if (!view || view.id !== id || !Array.isArray(log)) return;     // closed meanwhile, or the session is gone
  const sig = JSON.stringify(log);
  if (sig === view.logSig) return;
  const first = !view.logSig;
  view.logSig = sig;
  const box = view.el.querySelector(".log");
  const atEnd = first || box.scrollHeight - box.scrollTop - box.clientHeight < AT_END_PX;
  box.innerHTML = log.map(line).join("") || '<div class="msg tool">Nothing said yet</div>';
  if (atEnd) box.scrollTop = box.scrollHeight;
}

function label(s) {
  if (s.state === "permission") return ["Permission", "var(--caution)"];
  if (s.state === "working") return [`Working · ${since(s.started)}`, "var(--dim)"];
  if (s.wants && !s.done) return ["Your turn", "var(--primary)"];
  return s.done ? ["Done", "var(--ok)"] : ["Waiting", "var(--dim)"];
}

// Close session first, apart from the rest: it ends the session
const CLOSE = `<button class="pill quiet danger" data-act="close">${icon("x", 16)}Close session</button>`;

function buttons(s) {
  if (s.state === "permission") {
    const p = s.permission;
    return `<div class="code">${esc(p.tool)}${p.what ? ": " + esc(p.what) : ""}</div>${CLOSE}<span class="spacer"></span>
      <button class="pill" data-act="deny">Deny</button>
      ${p.allow ? `<button class="pill main" data-act="allow">${icon("check", 16, 2.2)}Allow</button>` : ""}`;
  }
  if (s.state === "working") {
    return `${CLOSE}<span class="spacer"></span>
      <button class="pill quiet" data-act="stop">${icon("square", 14, 2.2)}Stop</button>`;
  }
  return `${CLOSE}${s.asks ? `<span class="meta">${ASKS} Answer it on the desktop.</span>` : ""}<span class="spacer"></span>
    <button class="pill main" data-act="answer">${icon("mic", 16)}Answer</button>`;
}

// The head and the buttons follow the state; the log has its own timer
function frame(state) {
  if (!view) return;
  const s = state?.sessions?.find(x => x.id === view.id);
  const [text, colour] = s ? label(s) : ["Ended", "var(--dim)"];
  const head = `<div class="who"><b>${esc(s ? s.name || s.project : "The session has ended")}</b><span>${esc(s?.name ? s.project : "")}</span></div>
    <span class="spacer"></span><span class="sec" style="color:${colour}">${esc(text)}</span>
    <button class="close" aria-label="Close">${icon("x", 20)}</button>`;
  const foot = s ? buttons(s) : "";
  const sig = head + foot;
  if (sig === view.frameSig) return;
  view.frameSig = sig;
  view.el.querySelector(".dhead").innerHTML = head;
  view.el.querySelector(".dfoot").innerHTML = foot;
}

subscribe(frame);
