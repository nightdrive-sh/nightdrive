// The page: the bar at the top (the computer, what needs you, the plan's usage, the time) and the theme's colours.
// The tiles, dictation and actions are their own files; each listens to the state.
import { connect, esc, store, subscribe } from "./api.js";
import "./sessions.js";
import "./dictate.js";
import "./actions.js";

const top = document.querySelector(".top");
const ROLES = ["primary", "accent", "sel", "hover", "card", "border", "text", "muted", "dim", "soft"];

function theme(t) {
  for (const r of ROLES) if (t?.[r]) document.documentElement.style.setProperty(`--${r}`, t[r]);
  if (t?.primary) document.querySelector('meta[name="theme-color"]').content = "#0b0b0d";
}

function meter(w, label) {
  if (!w) return "";
  const t = w.resetsAt ? new Date(w.resetsAt) : null;
  const when = t && !isNaN(t) ? (t - Date.now() < 864e5 ? t.toTimeString().slice(0, 5) : t.toLocaleDateString([], { weekday: "short" })) : "";
  return `<div class="meter"><div><span>${label} ${Math.round(w.percent)}%</span><span>${when ? "resets " + when : ""}</span></div>
    <div class="bar"><div style="width:${Math.min(100, w.percent)}%"></div></div></div>`;
}

function render(state) {
  const list = state?.sessions || [];
  const need = list.filter(s => s.wants).length, work = list.filter(s => s.state === "working").length;
  const win = state?.usage?.windows || [];
  top.innerHTML = `
    <div class="brand"><b>N█</b><span>${esc(state?.host || "Nightdrive")}</span><i class="link ${store.online ? "" : "off"}"
      title="${store.online ? "Connected" : "No connection"}"></i></div>
    ${state?.demo ? '<span class="demo">Demo</span>' : ""}
    <div class="summary">${need ? `<i></i><span>${need} need${need === 1 ? "s" : ""} you</span>` : ""}
      ${work ? `<span>${need ? "· " : ""}${work} working</span>` : ""}</div>
    <span class="spacer"></span>
    ${meter(win.find(w => w.key === "session"), "5-hour")}${meter(win.find(w => w.key === "weekly"), "Week")}
    <span class="clock">${new Date().toTimeString().slice(0, 5)}</span>`;
  theme(state?.theme);
  document.title = need ? `(${need}) Nightdrive` : "Nightdrive";
}

subscribe(render);
setInterval(() => render(store.state), 20000);
render(null);
connect();
