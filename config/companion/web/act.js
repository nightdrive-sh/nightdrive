// What a session's buttons do, on its tile (sessions.js) and in its own view (detail.js): one request each
// (protocol.md › Sessions), Answer opening the sheet to dictate into it.
import { ask, post, store } from "./api.js";
import { compose } from "./compose.js";

// A question with choices (AskUserQuestion) shows only in the terminal: Claude Code writes it nowhere until answered
export const ASKS = "It asks you something in its terminal.";

export async function act(id, what, button = null) {
  const s = store.state?.sessions.find(x => x.id === id);
  if (what === "answer") return compose(id);
  const name = s?.name || s?.project || "the session";
  if (what === "stop" && !await ask("Stop", `Stop what ${name} is doing? Esc in its window.`, "Stop")) return;
  if (what === "close" && !await ask("Close session", `Close ${name}? Its window closes on the computer.`, "Close", true)) return;
  if (button) button.disabled = true;
  // An answer names the request it was shown, so it can't answer a newer one
  const body = what === "allow" || what === "deny" ? { request: s?.permission?.request } : undefined;
  const ok = await post(`/api/sessions/${encodeURIComponent(id)}/${what}`, body);
  if (button) button.disabled = false;
  return ok;
}
