// What a session's buttons do, on its tile (sessions.js) and in its own view (detail.js): one request each
// (protocol.md › Sessions), Answer opening the sheet to dictate into it.
import { ask, post, store } from "./api.js";
import { compose } from "./compose.js";
import { openPermission } from "./permission.js";

// A question with choices (AskUserQuestion) that Companion can't answer (the hook stopped waiting, or you were in its
// window): only the terminal shows it, as Claude Code writes it nowhere until answered. Otherwise question.js has it.
// A state, not something to do here: grey and in brackets, as Claude Code's own notes ([Request interrupted by user]).
export const ASKS = "[Claude asks you something in its terminal]";

export async function act(id, what, button = null) {
  const s = store.state?.sessions.find(x => x.id === id);
  if (what === "answer") return compose(id);
  if (what === "review") return openPermission(id);      // the request whole, its Allow after it
  const name = s?.name || s?.project || "the session";
  if (what === "stop" && !await ask("Stop", `Stop what ${name} is doing? Esc in its window.`, "Stop")) return;
  if (what === "close" && !await ask("End", `End ${name}? Its window closes on the computer.`, "End", true)) return;
  if (button) button.disabled = true;
  // An answer names the request it was shown, so it can't answer a newer one
  const body = what === "allow" || what === "deny" ? { request: s?.permission?.request } : undefined;
  const ok = await post(`/api/sessions/${encodeURIComponent(id)}/${what}`, body);
  if (button) button.disabled = false;
  return ok;
}
