// The session tiles: one per Claude Code session, each in its place (the server orders them as they started), and a tile
// for a new one. A permission request is answered here (an edit, a write, an MCP tool after Review shows it whole:
// permission.js); a question with choices with Question (its box, question.js),
// anything else with Answer (dictation into that session). A tap
// on a tile, off its buttons, brings its window up on the desktop; Show opens the session's own view (detail.js), and so
// does the tap while you're away from the computer (presence.js). The buttons' requests are act.js's.
import { esc, subscribe } from "./api.js";
import { icon } from "./icons.js";
import { compose } from "./compose.js";
import { act, ASKS } from "./act.js";
import { holdToTalk, Recognition } from "./speech.js";
import { send } from "./compose.js";
import { openDetail } from "./detail.js";
import { openQuestion } from "./question.js";
import { away } from "./presence.js";

const grid = document.querySelector(".sessions");

// A tile's message without Markdown's marks (bold, code, a heading's #): the full view renders them, here they're noise
function plain(text) {
  return text.replace(/\*\*|__|`/g, "").replace(/^#+\s+/, "").replace(/^\s*[-*]\s+/, "");
}

// The title: the state's icon as the sessions bar has it (SessionChip.qml), and the session's name
function head(s) {
  const [glyph, colour] = mark(s);
  return `<div class="head">
    <span style="color:${colour}">${glyph}</span>
    <span class="name">${esc(s.name || s.project)}</span>
    ${s.wants && s.state !== "permission" ? '<span class="unseen" aria-label="Unseen"></span>' : ""}</div>`;
}

// Asking you something (a permission request, a question in its terminal): the question in red, even a PM's; a PM:
// the robot, breathing while it works, never done; working: the turning spinner; finished while you were away: your
// turn; done (its last reply signs off with ✅): the green check; otherwise waiting: the grey prompt
function mark(s) {
  if (s.state === "permission" || s.asks) return [icon("message-circle-question", 18, 2), "var(--danger)"];
  if (s.pm) return [s.state === "working" ? `<span class="breathe">${icon("bot")}</span>` : icon("bot"), "var(--accent)"];
  if (s.state === "working") return [`<span class="spin">${icon("loader")}</span>`, "var(--text)"];
  if (s.wants && !s.done) return [icon("message", 18, 2), "var(--primary)"];
  if (s.done) return [icon("circle-check-big", 18, 2), "var(--ok)"];
  return [icon("chevron-right", 18, 2), "var(--dim)"];
}

function permission(s) {
  const p = s.permission;
  return `<article class="tile permission" data-act="focus" data-id="${esc(s.id)}">
    ${head(s)}
    ${p.allow ? `<div class="code">${esc(p.tool)}${p.what ? ": " + esc(p.what) : ""}</div>`
              : '<div class="meta">Too long to show here whole: tap to answer in its terminal.</div>'}
    <div class="fill"></div>
    <div class="row">
      <button class="pill" data-act="open" data-id="${esc(s.id)}">${icon("show", 16)}Show</button>
      <button class="pill" data-act="deny" data-id="${esc(s.id)}">Deny</button>
      ${p.review ? `<button class="pill main" data-act="review" data-id="${esc(s.id)}">${icon("shield", 16)}Review</button>`
        : p.allow ? `<button class="pill main" data-act="allow" data-id="${esc(s.id)}">${icon("check", 16, 2.2)}Allow</button>` : ""}
    </div></article>`;
}

// What it asks with choices: the first question (and how many more), Question opens them with their buttons
function question(s) {
  const qs = s.question.questions;
  return `<article class="tile ask" data-act="focus" data-id="${esc(s.id)}">
    ${head(s)}
    <div class="say">${esc(qs[0].question)}${qs.length > 1 ? ` <span class="more-q">+${qs.length - 1} more</span>` : ""}</div>
    <div class="fill"></div>
    <div class="row">
      <button class="pill" data-act="open" data-id="${esc(s.id)}">${icon("show", 16)}Show</button>
      <button class="pill main" data-act="question" data-id="${esc(s.id)}">${icon("message-circle-question", 16)}Question</button>
    </div></article>`;
}

function waiting(s) {
  if (s.question) return question(s);
  const asks = s.wants && !s.done;
  return `<article class="tile ${asks ? "ask" : s.done && !s.pm ? "done" : ""}" data-act="focus" data-id="${esc(s.id)}">
    ${head(s)}
    ${s.asks ? `<div class="meta asks">${ASKS} Tap the tile to answer there.</div>`     // the help alone: room for the buttons
             : s.last ? `<div class="say">${esc(plain(s.last))}</div>` : ""}
    <div class="fill"></div>
    <div class="row">
      <button class="pill" data-act="open" data-id="${esc(s.id)}">${icon("show", 16)}Show</button>
      <button class="pill main" data-act="answer" data-id="${esc(s.id)}">${icon("mic", 16)}Answer</button>
    </div></article>`;
}

// At work it still takes words, as its terminal does mid-turn (Claude Code reads them as soon as it can): Answer beside
// Stop
function working(s) {
  return `<article class="tile" data-act="focus" data-id="${esc(s.id)}">
    ${head(s)}
    ${s.last ? `<div class="code quiet">${esc(s.last)}</div>` : ""}
    <div class="fill"></div>
    <div class="row">
      <button class="pill" data-act="open" data-id="${esc(s.id)}">${icon("show", 16)}Show</button>
      <button class="pill quiet" data-act="stop" data-id="${esc(s.id)}">${icon("square", 14, 2.2)}Stop</button>
      <button class="pill main" data-act="answer" data-id="${esc(s.id)}">${icon("mic", 16)}Answer</button>
    </div></article>`;
}

const NEW_TILE = `<button class="tile new" data-act="new">${icon("plus", 28)}
  <span>New session</span><span>in ~/Projects: dictate its task</span></button>`;

let last = "";
let lastState = null;
function render(state) {
  lastState = state;
  const list = state?.sessions || [];
  const html = list.map(s => s.state === "permission" ? permission(s) : s.state === "waiting" ? waiting(s) : working(s)).join("")
    + (list.length ? "" : '<div class="empty">No Claude Code sessions on the desktop.</div>') + NEW_TILE;
  if (holding) return;            // not under a held Answer: the button would go from under the finger
  if (html !== last) { grid.innerHTML = html; last = html; fitLines(); answers(); }
}

// A tile's Answer held: talk and let go, the words go into its session (as the panel's button, speech.js); a tap
// opens the box as before. While one is held the tiles aren't redrawn, and the tile shows the words as they come.
let holding = false;
function answers() {
  if (!Recognition) return;       // no speech recognition: Answer opens the box (the click, below)
  for (const b of grid.querySelectorAll('button[data-act="answer"]')) {
    const id = b.dataset.id;
    const tile = b.closest(".tile");
    const words = () => tile.querySelector(".say") || tile.querySelector(".fill");
    holdToTalk(b, {
      started: () => { holding = true; },
      heard: w => { const el = words(); el.className = "say"; el.textContent = `“${w}”`; },
      tapped: () => { holding = false; compose(id); render(lastState); },
      done: w => {
        holding = false;
        last = "";                // back to the tile as it was, the words gone
        render(lastState);
        if (w) send(id, w);
      },
    });
  }
}

// A tile's message fills the room it has; when there is more of it, its bottom edge fades out (app.css .say.more),
// so a line cut by the edge doesn't read as the end
function fitLines() {
  for (const el of grid.querySelectorAll(".say")) el.classList.toggle("more", el.scrollHeight > el.clientHeight + 1);
}
new ResizeObserver(fitLines).observe(grid);

// A tap on a tile flashes its border: the window comes up on the computer, which you may not be looking at
function flash(tile) {
  tile.classList.remove("flash");
  void tile.offsetWidth;          // the animation starts again on a second tap
  tile.classList.add("flash");
  tile.addEventListener("animationend", () => tile.classList.remove("flash"), { once: true });
}

grid.addEventListener("click", e => {
  const b = e.target.closest("[data-act]");
  if (!b) return;
  const { act: what, id } = b.dataset;
  if (what === "new") return compose("new");
  if (what === "open") return openDetail(id);
  if (what === "question") return openQuestion(id);
  if (what === "answer" && Recognition) return;    // held or tapped: answers() has it
  if (what === "focus" && away()) return openDetail(id);   // nobody at the computer to see the window come up
  if (b.tagName === "ARTICLE") flash(b);
  act(id, what, b);
});

subscribe(render);
