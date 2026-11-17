// The session tiles: one per Claude Code session, the ones that need you first (the server orders them), and a tile
// for a new one. A permission request is answered here; a question with Answer (dictation into that session).
import { esc, post, since, store, subscribe, toast } from "./api.js";
import { icon } from "./icons.js";
import { compose } from "./dictate.js";

const grid = document.querySelector(".sessions");

function head(s, glyph, colour, right) {
  return `<div class="head">
    <span style="color:${colour}">${glyph}</span>
    <span class="name">${esc(s.project)}</span>
    ${s.wants && s.state !== "permission" ? '<span class="unseen" aria-label="Unseen"></span>' : ""}
    <span class="spacer"></span>${right}</div>
    ${s.topic ? `<div class="topic">${esc(s.topic)}</div>` : ""}`;
}

function permission(s) {
  const p = s.permission;
  return `<article class="tile permission">
    ${head(s, icon("shield"), "var(--caution)", '<span class="sec" style="color:var(--caution)">Permission</span>')}
    <div class="code">${esc(p.tool)}${p.what ? ": " + esc(p.what) : ""}</div>
    <div class="fill"></div>
    ${p.allow ? "" : '<div class="meta">Shows only part of what it allows: answer Allow in its terminal</div>'}
    <div class="row">
      <button class="pill" data-act="deny" data-id="${esc(s.id)}">Deny</button>
      ${p.allow ? `<button class="pill main" data-act="allow" data-id="${esc(s.id)}">${icon("check", 16, 2.2)}Allow</button>`
                : `<button class="pill main" data-act="focus" data-id="${esc(s.id)}">${icon("show", 16)}Show on desktop</button>`}
    </div></article>`;
}

function waiting(s) {
  const asks = s.wants;
  return `<article class="tile ${asks ? "ask" : ""}">
    ${head(s, icon(asks ? "message" : "check", 18, 2), asks ? "var(--primary)" : "var(--ok)",
           `<span class="sec" style="color:${asks ? "var(--primary)" : "var(--ok)"}">${asks ? "Your turn" : "Waiting"}</span>`)}
    ${s.last ? `<div class="say">${esc(s.last)}</div>` : ""}
    <div class="fill"></div>
    <div class="row">
      <button class="pill" data-act="focus" data-id="${esc(s.id)}">${icon("show", 16)}Show</button>
      <button class="pill main" data-act="answer" data-id="${esc(s.id)}">${icon("mic", 16)}Answer</button>
    </div></article>`;
}

function working(s) {
  return `<article class="tile">
    ${head(s, icon("terminal"), "var(--dim)",
           `<span class="dots" aria-label="Working"><span></span><span></span><span></span></span><span class="meta">${since(s.started)}</span>`)}
    ${s.last ? `<div class="code quiet">${esc(s.last)}</div>` : ""}
    <div class="fill"></div>
    <div class="row">
      <span class="spacer"></span>
      <button class="pill" data-act="focus" data-id="${esc(s.id)}">${icon("show", 16)}Show</button>
      <button class="pill quiet" data-act="stop" data-id="${esc(s.id)}">${icon("square", 14, 2.2)}Stop</button>
    </div></article>`;
}

const NEW_TILE = `<button class="tile new" data-act="new">${icon("plus", 28)}
  <span>New session</span><span>in ~/Projects: dictate its task</span></button>`;

let last = "";
function render(state) {
  const list = state?.sessions || [];
  const html = list.map(s => s.state === "permission" ? permission(s) : s.state === "waiting" ? waiting(s) : working(s)).join("")
    + (list.length ? "" : '<div class="empty">No Claude Code sessions on the desktop.</div>') + NEW_TILE;
  if (html !== last) { grid.innerHTML = html; last = html; }
}

grid.addEventListener("click", async e => {
  const b = e.target.closest("[data-act]");
  if (!b) return;
  const { act, id } = b.dataset;
  const s = store.state?.sessions.find(x => x.id === id);
  if (act === "answer") return compose(id);
  if (act === "new") return compose("new");
  if (act === "stop" && !confirm(`Stop what ${s?.project || "the session"} is doing (Esc)?`)) return;
  b.disabled = true;
  const ok = await post(`/api/sessions/${encodeURIComponent(id)}/${act}`);
  if (ok && act === "focus") toast(`${s?.project || "Its window"} is on the desktop now`);
  b.disabled = false;
});

subscribe(render);
setInterval(() => { last = ""; render(store.state); }, 30000);   // the minutes on working tiles
