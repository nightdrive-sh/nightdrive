// A question with choices (AskUserQuestion), answered here: each question, its choices as buttons with what each means,
// and Own answer to dictate or write one instead (the terminal's "Type something"). In the session's own view
// (detail.js) it sits above its buttons; a tile's Question opens it in a box of its own (openQuestion).
// One question with one choice to pick is answered at the tap, as in the terminal; otherwise the picks wait for Send.
// The answers go back as the terminal gives them (protocol.md › Sessions, reply): a choice's label, several joined
// with ", ", your own words after them.
import { esc, post, sheet, store, subscribe, toast } from "./api.js";
import { icon } from "./icons.js";
import { compose } from "./compose.js";

// What was picked, per request (so a redraw of the view keeps it): question index → { labels: Set, own: "" }
const picks = new Map();
// Answers on their way, per request: the button that sent them ("q:o" a choice, "own:q", "send") turns until the
// session takes them and the question goes, so a tap that answers at once shows it did something (#3138). Given up
// after PENDING_MS (the buttons come back), in case the session never takes it.
const pending = new Map();
const PENDING_MS = 10000;
const SPIN = `<span class="spin">${icon("loader", 16, 2.2)}</span>`;

function session(id) {
  return store.state?.sessions?.find(x => x.id === id);
}

function picked(q) {
  if (!picks.has(q.request)) picks.set(q.request, q.questions.map(() => ({ labels: new Set(), own: "" })));
  return picks.get(q.request);
}

// One question, one choice: no Send, the tap answers
function atOnce(q) {
  return q.questions.length === 1 && !q.questions[0].multiSelect;
}

// The answer to question i, as the terminal would give it; "" while none is picked
function answerOf(q, i) {
  const p = picked(q)[i];
  const labels = q.questions[i].options.map(o => o.label).filter(l => p.labels.has(l));
  return [...labels, p.own].filter(Boolean).join(", ");
}

export function questionHTML(s) {
  const q = s.question;
  const p = picked(q);
  const busy = pending.get(q.request);
  const off = busy ? " disabled" : "";
  const mark = (key, on) => busy === key ? SPIN : on ? icon("check", 16, 2.4) : "";
  const blocks = q.questions.map((x, i) => {
    const opts = x.options.map((o, j) => {
      const on = p[i].labels.has(o.label);
      return `<button class="opt${on ? " on" : ""}${busy === `${i}:${j}` ? " busy" : ""}" data-q="${i}" data-o="${j}" aria-pressed="${on}"${off}>
        <b>${esc(o.label)}</b>${o.description ? `<span>${esc(o.description)}</span>` : ""}
        <i>${mark(`${i}:${j}`, on)}</i></button>`;
    }).join("");
    const own = p[i].own;
    return `<section class="q">
      <div class="qhead">${x.header ? `<span class="sec">${esc(x.header)}</span>` : ""}
        <span class="qmode">${x.multiSelect ? "Pick any" : "Pick one"}</span></div>
      <div class="qtext">${esc(x.question)}</div>
      <div class="opts">${opts}
        <button class="opt own${own ? " on" : ""}${busy === `own:${i}` ? " busy" : ""}" data-q="${i}" data-own="1"${off}>
          <b>${icon("mic", 15)}Own answer</b><span>${own ? `“${esc(own)}”` : "Dictate or write it"}</span>
          <i>${mark(`own:${i}`, own)}</i></button>
      </div></section>`;
  }).join("");
  const ready = q.questions.every((_, i) => answerOf(q, i));
  return `<div class="qs${busy ? " sending" : ""}" data-id="${esc(s.id)}" data-request="${esc(q.request)}">${blocks}
    ${atOnce(q) ? "" : `<div class="qsend"><span class="spacer"></span>
      <button class="pill main" data-send="1"${ready && !busy ? "" : " disabled"}>${busy === "send" ? SPIN : icon("send", 16)}${
        busy === "send" ? "Sending…" : "Send answers"}</button></div>`}</div>`;
}

// The open panel of that request drawn again (picks, pending), if one is open
function redrawRequest(request) {
  const box = document.querySelector(`.qs[data-request="${CSS.escape(request)}"]`);
  if (box) redraw(box);
}

// key: the button that sends them, which turns while they're on their way
async function send(id, q, key) {
  const answers = Object.fromEntries(q.questions.map((x, i) => [x.question, answerOf(q, i)]));
  pending.set(q.request, key);
  redrawRequest(q.request);
  const ok = await post(`/api/sessions/${encodeURIComponent(id)}/reply`, { request: q.request, answers });
  if (!ok) {
    pending.delete(q.request);
    redrawRequest(q.request);
    return ok;
  }
  toast("Answered");
  setTimeout(() => {
    if (pending.get(q.request) !== key) return;
    pending.delete(q.request);
    picks.delete(q.request);
    redrawRequest(q.request);
  }, PENDING_MS);
  return ok;
}

// Draws the panel again with its picks, in place, where it was scrolled to: a new panel began at the top, and a pick
// low in a long question jumped it out of sight (#3138)
function redraw(box) {
  const s = session(box.dataset.id);
  if (s?.question?.request !== box.dataset.request) return;
  const top = box.scrollTop;
  box.outerHTML = questionHTML(s);
  keepScroll(top, box.dataset.request);
}

// The panel of that request, drawn again, scrolled back to top (its own scroll: in the session's view it scrolls)
export function keepScroll(top, request) {
  const now = document.querySelector(`.qs[data-request="${CSS.escape(request)}"]`);
  if (now) now.scrollTop = top;
}

// A click in a panel: picks a choice, asks for your own words, or sends. true when it was the panel's; done(ok) runs
// after an answer is sent.
export function questionClick(e, done = () => {}) {
  const box = e.target.closest(".qs");
  const b = e.target.closest("button");
  if (!box || !b) return false;
  const s = session(box.dataset.id);
  const q = s?.question;
  if (!q || q.request !== box.dataset.request) { toast("It no longer asks that", true); return true; }
  const i = Number(b.dataset.q);
  const p = picked(q);
  if (pending.has(q.request)) return true;                // on its way already
  if (b.dataset.send) {
    send(s.id, q, "send").then(done);
    return true;
  }
  if (b.dataset.own) {
    const x = q.questions[i];
    compose(s.id, {
      title: x.header || "Own answer",
      words: async w => {
        p[i].own = w;
        if (!x.multiSelect) p[i].labels.clear();          // one pick: your words instead of a choice
        if (atOnce(q)) return send(s.id, q, `own:${i}`).then(ok => { done(ok); return ok; });
        const now = document.querySelector(`.qs[data-request="${CSS.escape(q.request)}"]`);
        if (now) redraw(now);
        return true;
      },
    });
    return true;
  }
  const label = q.questions[i]?.options[Number(b.dataset.o)]?.label;
  if (label === undefined) return true;
  if (q.questions[i].multiSelect) {
    p[i].labels.has(label) ? p[i].labels.delete(label) : p[i].labels.add(label);
  } else {
    p[i].labels = new Set([label]);
    p[i].own = "";
  }
  if (atOnce(q)) {
    send(s.id, q, `${i}:${b.dataset.o}`).then(done);
    return true;
  }
  redraw(box);
  return true;
}

// A tile's Question: the panel in a box over the page. It closes once answered, or when the session no longer asks it
// (answered on the computer).
export function openQuestion(id) {
  const s = session(id);
  if (!s?.question) return;
  const request = s.question.request;
  const box = sheet(`<div class="row"><span class="sec">${esc(s.name || s.project)}</span><span class="spacer"></span>
      <button class="close" aria-label="Close">${icon("x", 18)}</button></div>${questionHTML(s)}`,
    { cls: "question", onClose: () => stop() });
  box.el.querySelector(".close").onclick = box.close;
  box.el.addEventListener("click", e => questionClick(e, ok => { if (ok) box.close(); }));
  const stop = subscribe(state => {
    const now = state?.sessions?.find(x => x.id === id);
    if (now?.question?.request !== request) box.close();
  });
}
