// Dictation: hold the big button and talk, let go, read it, send. The words come from the browser's own speech
// recognition (Safari's: Apple's, the same as the keyboard's dictation); where there is none, a tap opens the text box,
// and the keyboard's microphone key dictates into it. Where the text goes: a session (into its prompt), the window that
// has the keyboard on the desktop, or a new session. By itself: the session that asks you something, else the window.
import { esc, post, sheet, store, subscribe, toast } from "./api.js";
import { icon } from "./icons.js";

const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
const LANGS = [...new Set([navigator.language, "fi-FI", "en-US"])];
const mic = document.querySelector(".mic");
const hint = document.querySelector(".dictate .hint");
const clock = document.querySelector(".dictate .time");
const chip = document.querySelector(".target");

let chosen = "auto";     // "auto" | a session's id | "window" | "new"

function lang() {
  try { return localStorage.getItem("companion.lang") || LANGS[0]; } catch { return LANGS[0]; }
}

function resolve(t) {
  const list = store.state?.sessions || [];
  if (t === "auto") {
    const asks = list.find(s => s.wants && s.state === "waiting");
    return asks ? asks.id : "window";
  }
  return t === "window" || t === "new" || list.some(s => s.id === t) ? t : "window";
}

function nameOf(t) {
  if (t === "window") return ["the window with the keyboard", ""];
  if (t === "new") return ["a new session", ""];
  const s = store.state?.sessions.find(x => x.id === t);
  return [s?.project || "a session", s?.topic || ""];
}

function options(selected) {
  const list = store.state?.sessions || [];
  return [["auto", "Automatic"], ...list.map(s => [s.id, `${s.project}${s.topic ? " · " + s.topic : ""}`]),
          ["window", "The window with the keyboard"], ["new", "A new session"]]
    .map(([v, l]) => `<option value="${esc(v)}" ${v === selected ? "selected" : ""}>${esc(l)}</option>`).join("");
}

function renderChip() {
  const [name, topic] = nameOf(resolve(chosen));
  chip.innerHTML = `<em>Into</em><b>${esc(name)}</b>${topic ? `<em>· ${esc(topic)}</em>` : ""}
    <span class="spacer"></span>${icon("chevron-down", 16)}<select aria-label="Where the text goes">${options(chosen)}</select>`;
  chip.querySelector("select").onchange = e => { chosen = e.target.value; renderChip(); };
}
subscribe(renderChip);

// Listening, while the button is held
let rec = null, heard = "", started = 0, ticker = null;

function listen() {
  heard = "";
  rec = new Recognition();
  rec.lang = lang();
  rec.continuous = true;
  rec.interimResults = true;
  rec.onresult = e => {
    heard = Array.from(e.results, r => r[0].transcript).join(" ").replace(/\s+/g, " ").trim();
    hint.textContent = heard ? `“${heard}”` : "Listening…";
  };
  rec.onerror = e => { if (e.error !== "aborted" && e.error !== "no-speech") toast(`Dictation: ${e.error}`, true); };
  rec.onend = () => { if (rec) done(); };
  try { rec.start(); } catch { rec = null; return; }
  mic.classList.add("on");
  hint.textContent = "Listening…";
  started = Date.now();
  ticker = setInterval(() => { clock.textContent = `0:${String(Math.floor((Date.now() - started) / 1000)).padStart(2, "0")}`; }, 250);
}

function done() {
  const r = rec;
  rec = null;
  clearInterval(ticker);
  clock.textContent = "";
  mic.classList.remove("on");
  hint.textContent = "Hold to talk, let go to read it";
  try { r?.stop(); } catch {}
  if (heard) compose(chosen, heard);
}

if (Recognition) {
  mic.addEventListener("pointerdown", e => { e.preventDefault(); if (!rec) listen(); });
  mic.addEventListener("pointerup", () => { if (rec) setTimeout(() => rec && done(), 400); });   // the last words
  mic.addEventListener("pointercancel", () => rec && done());
  mic.addEventListener("contextmenu", e => e.preventDefault());
} else {
  hint.textContent = "Tap, then the keyboard's microphone";
  mic.addEventListener("click", () => compose(chosen));
}

// The sheet: the words to read and fix, where they go, and Send
export function compose(target = chosen, text = "") {
  let t = resolve(target);
  const s = sheet(`
    <div class="row"><span class="sec">Send</span><span class="spacer"></span>
      <label>Language <select class="lang">${LANGS.map(l => `<option ${l === lang() ? "selected" : ""}>${l}</option>`).join("")}</select></label></div>
    <div class="target"></div>
    <textarea placeholder="Say it or write it">${esc(text)}</textarea>
    <label><input type="checkbox" class="enter"> Press Enter: send it as the prompt</label>
    <div class="row"><button class="pill cancel">Cancel</button>
      <button class="pill main go">${icon("send", 16)}Send</button></div>`);
  const area = s.el.querySelector("textarea");
  const enter = s.el.querySelector(".enter");
  const box = s.el.querySelector(".target");
  const draw = () => {
    const [name, topic] = nameOf(t);
    box.innerHTML = `<em>Into</em><b>${esc(name)}</b>${topic ? `<em>· ${esc(topic)}</em>` : ""}<span class="spacer"></span>
      ${icon("chevron-down", 16)}<select aria-label="Where the text goes">${options(t)}</select>`;
    box.querySelector("select").onchange = e => { t = resolve(e.target.value); enter.checked = t !== "window"; draw(); };
  };
  enter.checked = t !== "window";
  draw();
  s.el.querySelector(".lang").onchange = e => { try { localStorage.setItem("companion.lang", e.target.value); } catch {} };
  s.el.querySelector(".cancel").onclick = s.close;
  s.el.querySelector(".go").onclick = async () => {
    const words = area.value.trim();
    if (!words) return area.focus();
    const path = t === "window" ? "/api/send" : t === "new" ? "/api/sessions/new" : `/api/sessions/${encodeURIComponent(t)}/send`;
    if (await post(path, { text: words, submit: enter.checked })) {
      s.close();
      toast(t === "new" ? "A new session starts on the desktop" : `Sent to ${nameOf(t)[0]}`);
    }
  };
  if (!text) area.focus();
}
