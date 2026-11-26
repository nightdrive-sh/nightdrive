// A session's steps in its view, kept quiet. The terminal shows each step anyway; here the texts are what you read.
// A turn (what came after one of your prompts) is folded up to its newest text (#3330): its steps, and Claude's short
// texts between them ("Checking the tests…"), are one line, "14 steps, 3 notes · Bash, Read, Edit", that a tap opens
// (another closes it). Folding only the runs between two texts (#3218) wasn't enough: Claude says a line between most
// calls, so runs were one or two steps long and the view was still a column of them. So you see your prompt, the line,
// and the turn's newest text: its answer once it is done, what it is about while it works.
// After that text, a run of steps is one line too, and some stay in sight without a tap:
// - the newest, while the session works or waits for your permission, so you see it move on;
// - one that failed or that was denied (transcript.py marks them), in its own colour, so a broken command isn't missed.
//   In a turn's fold they are counted on its line instead ("2 failed", in that colour): the text after came later.
import { esc } from "./api.js";

const NAMES = 4;          // tools named on a line before "…"

// The log's lines as HTML: texts by text(e), steps gathered. live: the session is at work (or asks for a permission).
// open: the keys of the folds you opened, kept by the view across its refreshes (detail.js), so one stays open as the
// log moves on.
export function logHTML(log, { live, open, text }) {
  const out = [];
  for (let i = 0; i < log.length;) {
    if (isPrompt(log[i])) { out.push(text(log[i])); i++; continue; }
    let j = i;
    while (j < log.length && !isPrompt(log[j])) j++;
    out.push(turn(log, i, j, { live: live && j === log.length, open, text }));
    i = j;
  }
  return out.join("");
}

const isPrompt = e => e.role === "user" && e.kind !== "tool";

// log[i..j): one turn. Everything before its newest text is folded; that text shows, and the steps after it as a run.
function turn(log, i, j, { live, open, text }) {
  let t = j - 1;
  while (t >= i && log[t].kind === "tool") t--;
  const before = log.slice(i, Math.max(t, i));
  const out = [];
  if (before.some(e => e.kind === "tool") && before.length > 1) out.push(fold(before, key(log, i), open, text));
  else out.push(...before.map(e => e.kind === "tool" ? step(e, false) : text(e)));
  if (t >= i) out.push(text(log[t]));
  if (t + 1 < j) out.push(run(log.slice(t + 1, j), key(log, t + 1), { now: live, open }));
  return out.join("");
}

// A fold or a run is known by the line before it and its first, which stay the same as the log moves on: a turn's fold
// grows at its end, its start stays put
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

const broken = e => e.status === "error" || e.status === "denied";

function step(e, now) {
  if (now && (!e.status || e.status === "running")) return `<div class="msg tool now">${esc(doing(e.text))}</div>`;
  const mark = e.status === "error" ? " failed" : e.status === "denied" ? " denied" : "";
  const label = mark ? `<span class="why">${e.status === "error" ? "Failed" : "Denied"}</span>` : "";
  return `<div class="msg tool${mark}${now ? " now" : ""}">${label}${esc(e.text)}</div>`;
}

// The line that opens a fold or a run: how many (counts: HTML), then the tools by name
function head(k, opened, counts, steps) {
  const names = [...new Set(steps.map(e => e.text.split(":")[0]))];
  const list = names.length > NAMES ? `${names.slice(0, NAMES).join(", ")}, …` : names.join(", ");
  return `<button class="steps${opened ? " opened" : ""}" data-steps="${esc(k)}" aria-expanded="${opened}">
    ${counts} · ${esc(list)}</button>`;
}

// A turn's work before its newest text: closed, one line; opened, all of it in its place
function fold(items, k, open, text) {
  const steps = items.filter(e => e.kind === "tool");
  const notes = items.length - steps.length;
  const bad = steps.filter(broken).length;
  const counts = `<span class="n">${plural(steps.length, "step")}${notes ? `, ${plural(notes, "note")}` : ""}</span>` +
    (bad ? ` · <span class="bad">${bad} failed</span>` : "");
  const opened = open.has(k);
  const body = opened ? items.map(e => e.kind === "tool" ? step(e, false) : text(e)).join("") : "";
  return head(k, opened, counts, steps) + body;
}

const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

function run(steps, k, { now, open }) {
  const last = now ? steps.length - 1 : -1;
  // one step, or none that would hide: as they are
  const shown = steps.map((e, i) => i === last || broken(e));
  if (steps.length === 1 || shown.every(Boolean)) return steps.map((e, i) => step(e, i === last)).join("");
  const opened = open.has(k);
  // opened: every step in its place; closed: only those that stay in sight, under the line
  const body = steps.map((e, i) => (opened || shown[i]) ? step(e, i === last) : "").join("");
  return head(k, opened, `<span class="n">${plural(steps.length, "step")}</span>`, steps) + body;
}
