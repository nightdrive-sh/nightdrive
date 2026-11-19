// A session's steps in its view, kept quiet (#3218): a run of tool calls between two texts is one line, "8 steps ·
// Bash, Dashboard, Inbox", and a tap on it opens them (another closes them). The terminal shows each step anyway;
// here the texts are what you read. Some steps stay in sight without a tap:
// - one that failed or that was denied (transcript.py marks them), in its own colour, so a broken command isn't missed;
// - the newest, while the session works or waits for your permission, so you see it move on.
import { esc } from "./api.js";

const NAMES = 4;          // tools named on the line before "…"

// The log's lines as HTML: texts by text(e), steps gathered. live: the session is at work (or asks for a permission).
// open: the keys of the runs you opened, kept by the view across its refreshes.
export function logHTML(log, { live, open, text }) {
  const out = [];
  for (let i = 0; i < log.length;) {
    if (log[i].kind !== "tool") { out.push(text(log[i])); i++; continue; }
    let j = i;
    while (j < log.length && log[j].kind === "tool") j++;
    out.push(run(log.slice(i, j), key(log, i), { now: live && j === log.length, open }));
    i = j;
  }
  return out.join("");
}

// A run is known by the text before it and its first step, which stay the same as the log moves on
function key(log, i) {
  const before = i > 0 ? log[i - 1].text.slice(0, 60) : "";
  return `${before}|${log[i].text}`;
}

// What a tool does, said as what the session is doing now: Bash: make → Running make
const DOING = { Bash: "Running", Read: "Reading", Edit: "Editing", Write: "Writing", Grep: "Searching", Glob: "Finding",
                WebFetch: "Fetching", WebSearch: "Searching the web for", Agent: "Delegating", Skill: "Using skill",
                SendMessage: "Messaging", ToolSearch: "Loading tools" };

function doing(text) {
  const [, tool, what] = text.match(/^(\w+): (.*)$/) || [];
  return DOING[tool] ? `${DOING[tool]} ${what}` : text;
}

function step(e, now) {
  if (now && (!e.status || e.status === "running")) return `<div class="msg tool now">${esc(doing(e.text))}</div>`;
  const mark = e.status === "error" ? " failed" : e.status === "denied" ? " denied" : "";
  const label = mark ? `<span class="why">${e.status === "error" ? "Failed" : "Denied"}</span>` : "";
  return `<div class="msg tool${mark}${now ? " now" : ""}">${label}${esc(e.text)}</div>`;
}

function run(steps, k, { now, open }) {
  const last = now ? steps.length - 1 : -1;
  // one step, or none that would hide: as they are
  const shown = steps.map((e, i) => i === last || e.status === "error" || e.status === "denied");
  if (steps.length === 1 || shown.every(Boolean)) return steps.map((e, i) => step(e, i === last)).join("");
  const opened = open.has(k);
  const names = [...new Set(steps.map(e => e.text.split(":")[0]))];
  const list = names.length > NAMES ? `${names.slice(0, NAMES).join(", ")}, …` : names.join(", ");
  const head = `<button class="steps${opened ? " opened" : ""}" data-steps="${esc(k)}" aria-expanded="${opened}">
    <span class="n">${steps.length} steps</span> · ${esc(list)}</button>`;
  // opened: every step in its place; closed: only those that stay in sight, under the line
  const body = steps.map((e, i) => (opened || shown[i]) ? step(e, i === last) : "").join("");
  return head + body;
}
