// The Dictate panel: hold the big button and talk, let go and it is sent, with no box in between (speech.js listens).
// It types into the window that has the keyboard on the desktop, which the panel names under the button (the state's
// active): a session's with Enter, as its prompt, any other without. A session of your choice has its own Answer
// (compose.js). Where the browser has no speech recognition, a tap opens that box to write in.
import { esc, subscribe } from "./api.js";
import { icon } from "./icons.js";
import { holdToTalk, Recognition } from "./speech.js";
import { compose, send } from "./compose.js";

const mic = document.querySelector(".dictate .mic");
const hint = document.querySelector(".dictate .hint");
const clock = document.querySelector(".dictate .time");
const chip = document.querySelector(".dictate .target");
const SHOWN_MS = 4000;     // how long the words sent stay under the button

// Which window the button types into: an arrow and its name (a session's own, else the window's program). No menu
// here: redrawn with every state, a native one closed under your finger.
function renderChip(state) {
  const name = state?.active?.name || "the window with the keyboard";
  chip.innerHTML = `${icon("arrow-right", 16)}<b>${esc(name)}</b>`;
}
subscribe(renderChip);

// The seconds while it listens, and the words under the button: as you talk, and for a moment after they went
let ticker = null, shownTimer = null;
function tick(on) {
  clearInterval(ticker);
  clock.textContent = "";
  if (!on) return;
  const t0 = Date.now();
  ticker = setInterval(() => { clock.textContent = `0:${String(Math.floor((Date.now() - t0) / 1000)).padStart(2, "0")}`; }, 250);
}

if (Recognition) {
  holdToTalk(mic, {
    started: () => { clearTimeout(shownTimer); hint.textContent = "Listening…"; tick(true); },
    heard: words => { hint.textContent = `“${words}”`; },
    done: words => {
      tick(false);
      hint.textContent = words ? `“${words}”` : "";
      shownTimer = setTimeout(() => { hint.textContent = ""; }, SHOWN_MS);
      if (words) send("window", words);
    },
  });
} else {
  mic.addEventListener("click", () => compose("window"));
}
