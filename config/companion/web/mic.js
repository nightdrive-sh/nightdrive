// Nightdrive's iOS app as the computer's microphone (Dashboard #3173, protocol.md › The microphone). With the lid
// closed, the computer's dictation key asks the app to listen instead of the built-in microphone: this page says it is
// ready while it is shown, takes start, stop and abort on its event stream (api.js), listens with the app's own
// dictation (window.nightdrive) and sends the words back. The app shows a banner of its own while it listens, which the
// page can't hide; the Dictate panel shows the words as they come.
// In a browser, or an app older than bridge 2, none of this runs.
import { micDevice, onMic, post, store, subscribe } from "./api.js";
import { lang } from "./speech.js";

const app = window.nightdrive;
const READY_EVERY_MS = 10000;   // the server lets a ready go after 25 s without one
const READY_MIN_MS = 4000;      // a state's arrival says it again, but not more often than this
const LAST_WORDS_MS = 400;      // as holdToTalk: the key let go, it hears a moment longer for the last words
const panel = document.querySelector(".dictate");
const hint = panel?.querySelector(".hint");
const button = panel?.querySelector(".mic");

let rec = null, current = 0, stopping = null, readyAt = 0, wanted = null;

const shown = () => document.visibilityState === "visible";

function ready(on) {
  readyAt = on ? Date.now() : 0;
  post("/api/mic", { device: micDevice, name: app.device || "", ready: on }, { quiet: true });
}

function beat() {
  if (shown() && store.online && Date.now() - readyAt > READY_MIN_MS) ready(true);
}

function report(id, type, extra = {}) {
  post("/api/mic/event", { device: micDevice, id, type, ...extra }, { quiet: true });
}

function show(on, words = "") {
  panel?.classList.toggle("remote", on);
  button?.classList.toggle("on", on);
  const host = store.state?.host || "the computer";
  if (hint) hint.textContent = !on ? "" : words ? `“${words}”` : `Listening for ${host}…`;
}

function listen(id) {
  abort();
  current = id;
  let words = "", started = false;
  const r = rec = new app.SpeechRecognition();
  r.lang = lang();
  r.continuous = true;
  r.interimResults = true;
  r.remote = true;          // the app shows its banner: the computer listens, not a button held here
  r.onstart = () => { started = true; report(id, "started"); show(true); };
  r.onresult = e => {
    words = Array.from(e.results, x => x[0].transcript).join(" ").replace(/\s+/g, " ").trim();
    show(true, words);
  };
  // Before it listens an error fails the start (the computer then uses its own microphone); after, the words so far go
  r.onerror = e => { if (!started) report(id, "error", { error: e.error || "error" }); };
  r.onend = () => {
    if (rec === r) { rec = null; clearTimeout(stopping); show(false); }
    report(id, "text", { text: words });
  };
  try { r.start(); } catch { rec = null; report(id, "error", { error: "busy" }); }
}

function stop(id) {
  if (!rec || id !== current) return;
  clearTimeout(stopping);
  const r = rec;
  stopping = setTimeout(() => { try { r.stop(); } catch {} }, LAST_WORDS_MS);
}

// Dropped: the computer has given up on it (or the page goes away); nothing is sent
function abort() {
  if (!rec) return;
  const r = rec;
  rec = null;
  clearTimeout(stopping);
  r.onresult = r.onerror = r.onend = null;
  try { r.abort(); } catch {}
  show(false);
}

if (micDevice && app?.SpeechRecognition) {
  onMic(c => {
    if (c.op === "start") listen(c.id);
    else if (c.op === "stop") stop(c.id);
    else if (c.op === "abort" && c.id === current) abort();
  });
  setInterval(beat, READY_EVERY_MS);
  document.addEventListener("visibilitychange", () => {
    if (shown()) beat();
    else { ready(false); abort(); }
  });
  subscribe(state => {
    beat();
    // The computer wants this as its microphone (lid closed): the app keeps the screen on while charging
    const want = !!state?.mic?.wanted;
    if (want !== wanted) { wanted = want; app.microphone?.(want); }
  });
}
