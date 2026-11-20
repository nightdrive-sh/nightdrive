// Your words on their way into a session (pending.js), at the end of its view (detail.js): faded while they go, and
// when they didn't get there, in the danger colour with Send again (the same words, the same way) and × to drop them.
import { esc } from "./api.js";
import { icon } from "./icons.js";
import { forget, pending } from "./pending.js";

export function pendingHTML(id) {
  return pending(id).map(p => p.failed
    ? `<div class="msg you failed">${esc(p.text)}<div class="undelivered"><span>Didn't get there</span>
        <button class="pill" data-resend="${p.key}">${icon("send", 14)}Send again</button>
        <button class="drop" data-forget="${p.key}" aria-label="Remove">${icon("x", 16)}</button></div></div>`
    : `<div class="msg you sending" aria-label="Sending">${esc(p.text)}</div>`).join("");
}

// A click on a failed one's buttons; true when it was one. send(id, words) as compose.js's.
export function pendingClick(e, id, send) {
  const again = e.target.closest("button[data-resend]");
  const drop = e.target.closest("button[data-forget]");
  const key = again?.dataset.resend || drop?.dataset.forget;
  if (!key) return false;
  const p = pending(id).find(x => x.key === key);
  if (drop || !p) forget(id, key);
  else send(id, p.text);
  return true;
}
