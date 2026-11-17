// The plan's usage, in a box of its own: the top bar has only its icon (the gauge in the right corner). Each Claude
// account as the Claude menu has them (claude-usage --all, the state's usage): its 5-hour and week, and a model's own
// week, each with its bar and when it resets.
import { esc, sheet, store } from "./api.js";
import { icon } from "./icons.js";

const LABELS = { session: "5-hour", weekly: "Week" };
const DAY_MS = 864e5;

// "12:50" today, "Thu 23:59" later: the weekday in English, as the rest of the page
function when(iso) {
  const t = iso ? new Date(iso) : null;
  if (!t || isNaN(t)) return "";
  const time = t.toTimeString().slice(0, 5);
  return t - Date.now() < DAY_MS && t.getDate() === new Date().getDate()
    ? time : `${t.toLocaleDateString("en-GB", { weekday: "short" })} ${time}`;
}

function row(w) {
  const label = w.model ? `Week · ${w.model}` : LABELS[w.key] || w.key;
  const pct = Math.round(w.percent ?? 0);
  const reset = when(w.resetsAt);
  return `<div class="use-row">
    <div><span>${esc(label)}</span><b>${pct}%</b></div>
    <div class="bar"><div style="width:${Math.min(100, pct)}%"></div></div>
    ${reset ? `<div class="use-reset">reset ${esc(reset)}</div>` : ""}</div>`;
}

function account(a) {
  const head = `<span class="sec">${esc(a.account || "Claude")}</span>${a.plan ? `<span class="use-plan">${esc(a.plan)}</span>` : ""}`;
  const body = a.windows?.length ? a.windows.map(row).join("")
    : `<div class="meta">${esc(a.error || "No usage yet")}</div>`;
  return `<section class="use-acct"><div class="use-head">${head}</div>${body}</section>`;
}

export function openUsage() {
  const list = store.state?.usage;
  const accounts = Array.isArray(list) ? list : list ? [list] : [];
  const s = sheet(`
    <div class="row"><span class="sec">Usage</span><span class="spacer"></span>
      <button class="close" aria-label="Close">${icon("x", 18)}</button></div>
    ${accounts.length ? accounts.map(account).join("") : '<div class="meta">No usage from Claude yet</div>'}`);
  s.el.querySelector(".close").onclick = s.close;
}
