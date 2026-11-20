// A session's own view, over the whole screen: what it said and did lately (GET /api/sessions/ID/log: your prompts,
// Claude's texts, its tool calls), read again every REFRESH_MS while it is open, and the session's buttons below it.
// A tap on a tile opens it; × or Esc closes it. It stays at the end as new lines come, unless you scrolled up to read.
// A question with choices shows whole above the buttons, to answer there (question.js). Answer is held to talk, as
// on a tile (let go and it is sent; a tap opens its box), and Write beside it opens the box at its keyboard.
// Its steps (tool calls) are kept quiet, a run of them one line that a tap opens (steps.js).
// The view is a step in the browser's history, so Back (Android's, Safari's edge gesture in a tab) closes it; in the
// app on the home screen a swipe from the left edge does (swipe.js).
import { esc, get, since, store, subscribe } from "./api.js";
import { icon } from "./icons.js";
import { act, ASKS } from "./act.js";
import { compose, send } from "./compose.js";
import { holdToTalk, Recognition } from "./speech.js";
import { markdown } from "./markdown.js";
import { logHTML } from "./steps.js";
import { keepScroll, questionClick, questionHTML } from "./question.js";
import { edgeSwipe } from "./swipe.js";

const REFRESH_MS = 2000;
const AT_END_PX = 40;      // this close to the bottom still counts as following along
let view = null;           // { id, el, timer, log, logSig, headSig, footSig, holding, open: runs of steps opened }

export function openDetail(id) {
  // one step in the history however many views open one after another (a tile's Show over another's)
  if (history.state?.detail) history.replaceState({ detail: id }, ""); else history.pushState({ detail: id }, "");
  shut();
  const el = document.createElement("div");
  el.className = "detail";
  el.setAttribute("role", "dialog");
  el.innerHTML = '<header class="dhead"></header><div class="log"></div><footer class="dfoot"></footer>';
  document.body.append(el);
  view = { id, el, timer: setInterval(load, REFRESH_MS), log: [], logSig: "", headSig: "", footSig: "", holding: false,
           open: new Set() };
  el.addEventListener("click", e => {
    if (e.target.closest(".close")) return close();
    if (questionClick(e)) return;
    const run = e.target.closest("button[data-steps]");
    if (run) return toggle(run.dataset.steps);
    const b = e.target.closest("button[data-act]");
    if (b?.dataset.act === "write") return compose(view.id, { write: true });
    if (b?.dataset.act === "answer" && Recognition) return;    // held or tapped: talk() has it
    if (b) act(view.id, b.dataset.act, b).then(ok => { if (ok && b.dataset.act === "close") close(); });
  });
  edgeSwipe(el, close);
  frame(store.state);
  load();
}

// × , Esc, End and the swipe go back in the history; popstate then shuts the view, as it does for the browser's Back
function close() {
  if (history.state?.detail) history.back(); else shut();
}
addEventListener("popstate", () => { if (!history.state?.detail) shut(); });
// a reload with the view's step in the history opens the list: the step is left as nothing to go back to
if (history.state?.detail) history.replaceState(null, "");

function shut() {
  if (!view) return;
  clearInterval(view.timer);
  view.el.remove();
  view = null;
}
document.addEventListener("keydown", e => { if (e.key === "Escape" && !document.querySelector(".scrim")) close(); });

// Claude's texts are Markdown; your prompts are shown as they are, the steps by steps.js
function line(e) {
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
  view.log = log;
  draw(first);
}

// The newest step stays in sight while the session works or waits on a permission (steps.js)
function live() {
  const s = store.state?.sessions?.find(x => x.id === view.id);
  return s?.state === "working" || s?.state === "permission";
}

function draw(first) {
  const box = view.el.querySelector(".log");
  const atEnd = first || box.scrollHeight - box.scrollTop - box.clientHeight < AT_END_PX;
  view.live = live();
  box.innerHTML = logHTML(view.log, { live: view.live, open: view.open, text: line })
    || '<div class="msg tool">Nothing said yet</div>';
  if (atEnd) box.scrollTop = box.scrollHeight;
}

// A tap on a run's line opens its steps, another closes them; the log stays where it was scrolled
function toggle(k) {
  if (view.open.has(k)) view.open.delete(k); else view.open.add(k);
  const box = view.el.querySelector(".log"), top = box.scrollTop;
  draw(false);
  box.scrollTop = top;
}

function label(s) {
  if (s.state === "permission") return ["Permission", "var(--caution)"];
  if (s.state === "working") return [`Working · ${since(s.started)}`, "var(--dim)"];
  if (s.question) return ["Question", "var(--primary)"];
  if (s.wants && !s.done) return ["Your turn", "var(--primary)"];
  return s.done ? ["Done", "var(--ok)"] : ["Waiting", "var(--dim)"];
}

// End first, apart from the rest: it ends the session (its request is close, protocol.md)
const CLOSE = `<button class="pill quiet danger" data-act="close">${icon("x", 16)}End</button>`;

function buttons(s) {
  if (s.state === "permission") {
    const p = s.permission;
    // Review: the request whole before its Allow (permission.js); none: too long to show here
    return `<div class="code">${esc(p.tool)}${p.what ? ": " + esc(p.what) : ""}</div>${CLOSE}
      ${p.allow ? "" : '<span class="meta">[Too long to show here whole: answer it at the computer]</span>'}<span class="spacer"></span>
      <button class="pill" data-act="deny">Deny</button>
      ${p.review ? `<button class="pill main" data-act="review">${icon("shield", 16)}Review</button>`
        : p.allow ? `<button class="pill main" data-act="allow">${icon("check", 16, 2.2)}Allow</button>` : ""}`;
  }
  if (s.question) return `${questionHTML(s)}${CLOSE}`;    // its own answers in place of Answer: the terminal waits on it
  // At work it still takes words, as its terminal does mid-turn: Stop beside Write and Answer. Four on a phone's row:
  // Stop and Write give up their words there (.squeeze, app.css)
  if (s.state === "working") {
    return `${CLOSE}<span class="spacer"></span>
      <button class="pill quiet squeeze" data-act="stop" aria-label="Stop">${icon("square", 14, 2.2)}<span>Stop</span></button>
      ${TALK.replace('class="pill"', 'class="pill squeeze"')}`;
  }
  return `${CLOSE}${s.asks ? `<span class="meta">${ASKS}</span>` : ""}<span class="spacer"></span>
    ${TALK}`;
}

const TALK = `<button class="pill" data-act="write" aria-label="Write">${icon("keyboard", 16)}<span>Write</span></button>
    <button class="pill main" data-act="answer">${icon("mic", 16)}Answer</button>`;

// The head and the buttons follow the state; the log has its own timer
function frame(state) {
  if (!view) return;
  const s = state?.sessions?.find(x => x.id === view.id);
  const [text, colour] = s ? label(s) : ["Ended", "var(--dim)"];
  // Under the name, after its project: what it is doing (Working · 5 min), where the eye already is
  const what = `<em style="color:${colour}">${esc(text)}</em>`;
  const head = `<div class="who"><b>${esc(s ? s.name || s.project : "The session has ended")}</b><span>${s?.name ? `${esc(s.project)} · ${what}` : what}</span></div>
    <span class="spacer"></span><button class="close" aria-label="Close">${icon("x", 20)}</button>`;
  const foot = s ? buttons(s) : "";
  if (head !== view.headSig) { view.headSig = head; view.el.querySelector(".dhead").innerHTML = head; }
  if (view.logSig && live() !== view.live) draw(false);     // done now: its newest step goes into its run
  // the buttons stay as they are under a held Answer (not taken from under the finger), and when nothing changed
  if (view.holding || foot === view.footSig) return;
  view.footSig = foot;
  // a question's panel stays where you scrolled it: a pick leaves footSig behind, so the next state redraws it (#3138)
  const qs = view.el.querySelector(".dfoot .qs");
  const was = qs && [qs.scrollTop, qs.dataset.request];
  view.el.querySelector(".dfoot").innerHTML = foot;
  if (was) keepScroll(...was);
  talk();
}

// Answer held: the words show above the buttons as they come, and go into the session when you let go
function talk() {
  const b = view.el.querySelector('.dfoot button[data-act="answer"]');
  if (!b || !Recognition) return;
  const id = view.id;
  const heard = () => {
    let el = view?.el.querySelector(".dfoot .heard");
    if (view && !el) { el = document.createElement("div"); el.className = "heard"; view.el.querySelector(".dfoot").prepend(el); }
    return el;
  };
  const end = () => {
    if (!view) return;
    view.holding = false;
    view.el.querySelector(".dfoot .heard")?.remove();
    frame(store.state);
  };
  holdToTalk(b, {
    started: () => { view.holding = true; heard().textContent = "Listening…"; },
    heard: w => { const el = heard(); if (el) el.textContent = `“${w}”`; },
    tapped: () => { end(); compose(id); },
    done: w => { end(); if (w) send(id, w); },
  });
}

subscribe(frame);
