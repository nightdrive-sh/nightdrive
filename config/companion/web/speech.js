// Hold to talk, with the browser's own speech recognition (Safari's: Apple's, the same as the keyboard's dictation):
// hold a button and talk, let go and the words go to done(). The panel's big button (dictate.js) and the box's
// (compose.js) both use it. Where there is none, the callers fall back to writing.
import { toast } from "./api.js";

export const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
const LAST_WORDS_MS = 400;     // the recognizer still hears this long after you let go: the last words
const TAP_MS = 350;            // a press shorter than this, with no words, is a tap (tapped(), when given)

// The language it listens for: the device's own (one saved as companion.lang wins, for a later choice)
function lang() {
  try { return localStorage.getItem("companion.lang") || navigator.language || "fi-FI"; } catch { return navigator.language || "fi-FI"; }
}

// heard(words) as they come, started() when it listens, done(words) once when it stops ("" when nothing was heard);
// tapped(), when given, for a short press with no words instead of done("") (the tile's Answer: a tap opens its box)
export function holdToTalk(button, { heard = () => {}, started = () => {}, done, tapped = null }) {
  let rec = null, words = "", downAt = 0, upAt = 0;
  const finish = () => {
    const r = rec;
    rec = null;
    button.classList.remove("on");
    try { r?.stop(); } catch {}
    const said = words;
    words = "";            // given once, however many ways the listening ends
    // a tap: let go (upAt), quickly; not the recognizer ending by itself while the button is still held
    if (!said && tapped && upAt && upAt - downAt < TAP_MS) tapped(); else done(said);
  };
  const listen = () => {
    words = "";
    rec = new Recognition();
    rec.lang = lang();
    rec.continuous = true;
    rec.interimResults = true;
    rec.onresult = e => {
      words = Array.from(e.results, r => r[0].transcript).join(" ").replace(/\s+/g, " ").trim();
      heard(words);
    };
    rec.onerror = e => { if (e.error !== "aborted" && e.error !== "no-speech") toast(`Dictation: ${e.error}`, true); };
    rec.onend = () => { if (rec) finish(); };
    try { rec.start(); } catch { rec = null; return; }
    button.classList.add("on");
    started();
  };
  button.addEventListener("pointerdown", e => { e.preventDefault(); downAt = Date.now(); upAt = 0; if (!rec) listen(); });
  button.addEventListener("pointerup", () => {
    upAt = Date.now();
    if (rec) setTimeout(() => rec && finish(), LAST_WORDS_MS);
    else if (tapped && upAt - downAt < TAP_MS) tapped();     // it couldn't listen (no microphone): a tap still taps
  });
  button.addEventListener("pointercancel", () => rec && finish());
  button.addEventListener("contextmenu", e => e.preventDefault());
}
