// At the computer or away (protocol.md › State, "presence"): the switch in the top bar, and what a tap on a session's
// tile does. Away (the computer locked, idle five minutes, or set here), a tap opens the session's own view on the page;
// at the computer it brings the window up there, where you are looking. A tap on the switch sets it the other way; the
// server keeps that until the computer sees a change of its own (you lock it, leave it, or come back to it).
import { post, store } from "./api.js";

const WHY = { locked: "The computer is locked", idle: "No input on the computer for a while", set: "Set here" };

export function away() {
  return !!store.state?.presence?.away;
}

// The switch, for app.js's top bar: "Away" stands out (the tiles act differently), "At the computer" stays quiet
export function presenceSwitch(state) {
  const p = state?.presence;
  if (!p) return "";
  const title = p.away ? `${WHY[p.why] || "Away"}: a tap on a session shows it here. Tap to say you're at the computer.`
                       : `${p.set ? "Set here" : "In use"}: a tap on a session brings its window up there. Tap to say you're away.`;
  return `<button class="presence ${p.away ? "away" : ""}" title="${title}" aria-pressed="${p.away}">
    <i></i>${p.away ? "Away" : "At the computer"}</button>`;
}

export async function togglePresence(button) {
  button.disabled = true;
  await post("/api/presence", { away: !away() });
  button.disabled = false;
}
