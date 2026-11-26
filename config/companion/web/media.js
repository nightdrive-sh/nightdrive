// An Inbox message's sound and video files as players (#3331, protocol.md › Inbox), under its text with their names
// as links. The server answers byte ranges, which iOS needs to play at all (media.py). Audio the browser can't play
// (Ogg/Opus in Safari) is asked for as AAC (?as=m4a, converted once on the computer); if a file the browser said it
// might play fails after all, it gets the same second try. Video isn't converted: one it can't play stays a link.
import { esc } from "./api.js";
import { icon } from "./icons.js";

const probe = { audio: document.createElement("audio"), video: document.createElement("video") };
const M4A = "?as=m4a";

const kind = f => (f.type || "").split("/")[0];
export const isMedia = f => (kind(f) === "audio" || kind(f) === "video") && !!source(f);

// The address the player loads: the file itself, the converted one, or null (a link only)
function source(f) {
  const k = kind(f);
  if (probe[k]?.canPlayType(f.type)) return f.url;
  return k === "audio" ? f.url + M4A : null;
}

export function players(list) {
  if (!list.length) return "";
  return `<div class="imedia">${list.map(f => {
    const tag = kind(f), src = source(f);
    // data-key: the file, so a redraw of the same message keeps a player that is playing (keepPlayers)
    return `<figure><${tag} controls playsinline preload="metadata" src="${esc(src)}" data-key="${esc(f.url)}"></${tag}>
      <a href="${esc(f.url)}" target="_blank" rel="noopener">${icon("paperclip", 13)}<span>${esc(f.name)}</span></a>
      </figure>`;
  }).join("")}</div>`;
}

// write() replaces the pane's HTML: the players it had with the same files go back in place of the new ones, so a
// message read again (a stamp changed) doesn't stop what is playing. Moved within one task, they don't pause.
export function keepPlayers(pane, write) {
  const old = new Map([...pane.querySelectorAll(".imedia [data-key]")].map(m => [m.dataset.key, m]));
  write();
  for (const m of pane.querySelectorAll(".imedia [data-key]")) {
    const was = old.get(m.dataset.key);
    if (was && was.tagName === m.tagName) m.replaceWith(was);
  }
}

// A player's error (it doesn't bubble: caught on the way down): audio that failed as itself tries the AAC once
export function playerFallback(pane) {
  pane.addEventListener("error", e => {
    const m = e.target;
    if (m.tagName !== "AUDIO" || !m.dataset.key || m.src.endsWith(M4A)) return;
    m.src = m.dataset.key + M4A;
  }, true);
}
