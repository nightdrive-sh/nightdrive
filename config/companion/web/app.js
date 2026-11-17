// The page: the bar at the top (the computer, at it or away, what needs you, a new version to reload, the usage's
// icon) and the theme's colours.
// The tiles, dictation and actions are their own files; each listens to the state.
import { connect, esc, store, subscribe } from "./api.js";
import "./sessions.js";
import "./dictate.js";
import "./actions.js";
import { icon } from "./icons.js";
import { openUsage } from "./usage.js";
import { presenceSwitch, togglePresence } from "./presence.js";

const top = document.querySelector(".top");
let loadedWeb = null;     // the page files' stamp (server.web_version) this page was loaded with
top.addEventListener("click", e => {
  if (e.target.closest(".update")) location.reload();
  if (e.target.closest(".usage-btn")) openUsage();
  const p = e.target.closest(".presence");
  if (p) togglePresence(p);
});
const ROLES = ["primary", "accent", "sel", "hover", "card", "border", "text", "muted", "dim", "soft"];

function theme(t) {
  for (const r of ROLES) if (t?.[r]) document.documentElement.style.setProperty(`--${r}`, t[r]);
  if (t?.primary) document.querySelector('meta[name="theme-color"]').content = "#0b0b0d";
}


// Tiles from before the connection went are dimmed, so they don't pass for the present: after OFFLINE_MS, as a short
// break (the stream reconnecting, the iPad waking) mends itself before anyone could act on it
const OFFLINE_MS = 3000;
let offTimer = null;
function offline(on) {
  if (!on) {
    clearTimeout(offTimer);
    offTimer = null;
    document.body.classList.remove("offline");
  } else if (!offTimer) {
    offTimer = setTimeout(() => document.body.classList.add("offline"), OFFLINE_MS);
  }
}

function render(state) {
  const list = state?.sessions || [];
  // What needs you: one that asks you something (a PM's too), or one that finished while you were away, not done
  // with ✅ and not a PM (a project manager waits for you most of the time: it would always count)
  const need = list.filter(s => s.state === "permission" || s.asks || (s.wants && !s.done && !s.pm)).length;
  const work = list.filter(s => s.state === "working").length;
  if (state?.web) loadedWeb ??= state.web;
  const stale = state?.web && state.web !== loadedWeb;
  top.innerHTML = `
    <div class="brand"><img src="/logo.svg" height="18" alt="Nightdrive"><span>${esc(state?.host || "Nightdrive")}</span><i class="link ${store.online ? "" : "off"}"
      title="${store.online ? "Connected" : "No connection"}"></i></div>
    ${state?.demo ? '<span class="demo">Demo</span>' : ""}
    ${presenceSwitch(state)}
    <div class="summary">${need ? `<i></i><span>${need} need${need === 1 ? "s" : ""} you</span>` : ""}
      ${work ? `<span>${need ? "· " : ""}${work} working</span>` : ""}</div>
    <span class="spacer"></span>
    ${stale ? '<button class="update">New version available<b>Reload</b></button>' : ""}
    <button class="usage-btn" aria-label="Usage">${icon("gauge", 20)}</button>`;
  theme(state?.theme);
  offline(!store.online);
  document.title = need ? `(${need}) Nightdrive` : "Nightdrive";
}

subscribe(render);
setInterval(() => render(store.state), 20000);
render(null);
connect();
