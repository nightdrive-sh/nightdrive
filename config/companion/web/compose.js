// The box for a session's Answer and for a new session: its title says where the words go (the one it was opened for,
// no menu), the big button to hold and talk (let go and it is sent, as the panel's), and Write for the keyboard
// instead. Enter as the panel's: into a session as its prompt, into the window only when that window is a session's.
// With words, the box gives them to it instead of sending (a question's Own answer, question.js): it returns true
// when they went, and the box closes.
import { esc, post, sheet, store, toast } from "./api.js";
import { icon } from "./icons.js";
import { holdToTalk, Recognition } from "./speech.js";

// Where the words go, as a request, and what the toast says
function pathFor(t) {
  return t === "window" ? "/api/send" : t === "new" ? "/api/sessions/new" : `/api/sessions/${encodeURIComponent(t)}/send`;
}

function session(t) {
  return store.state?.sessions?.find(x => x.id === t);
}

function nameOf(t) {
  if (t === "window") return store.state?.active?.name || "the window with the keyboard";
  if (t === "new") return "a new session";
  const s = session(t);
  return s?.name || s?.project || "a session";
}

// Sends the words to t; true when it went. Shared with the panel (dictate.js).
export async function send(t, words) {
  const submit = t === "window" ? "session" : true;     // the server decides for the window, when it types
  const ok = await post(pathFor(t), { text: words, submit });
  if (ok) toast(t === "new" ? "A new session starts on the desktop" : `Sent to ${nameOf(t)}`);
  return ok;
}

export function compose(target = "window", { title: own, words: give } = {}) {
  const t = target === "window" || target === "new" || session(target) ? target : "window";
  const title = own || (t === "new" ? "New session" : t === "window" ? `Send to ${nameOf(t)}` : `Answer ${nameOf(t)}`);
  const deliver = give || (w => send(t, w));
  const s = sheet(`
    <div class="row"><span class="sec">${esc(title)}</span><span class="spacer"></span>
      <button class="close" aria-label="Close">${icon("x", 18)}</button></div>
    <button class="mic" aria-label="Hold to dictate">${icon("mic", 44, 1.6)}</button>
    <div class="hint said" aria-live="polite"></div>
    <div class="writing" hidden>
      <textarea placeholder="Write it"></textarea>
      <div class="row"><span class="spacer"></span><button class="pill main go">${icon("send", 16)}Send</button></div>
    </div>
    <div class="row"><button class="pill write">${icon("keyboard", 16)}Write</button></div>`);
  const said = s.el.querySelector(".said");
  const writing = s.el.querySelector(".writing");
  const area = s.el.querySelector("textarea");
  const write = () => {
    writing.hidden = false;
    s.el.querySelector(".write").parentElement.hidden = true;
    area.focus();
  };
  s.el.querySelector(".close").onclick = s.close;
  s.el.querySelector(".write").onclick = write;
  s.el.querySelector(".go").onclick = async () => {
    const words = area.value.trim();
    if (!words) return area.focus();
    if (await deliver(words)) s.close();
  };
  const mic = s.el.querySelector(".mic");
  if (!Recognition) {     // no speech recognition here: the keyboard's own microphone key dictates into the box
    mic.hidden = true;
    return write();
  }
  holdToTalk(mic, {
    started: () => { said.textContent = "Listening…"; },
    heard: words => { said.textContent = `“${words}”`; },
    done: async words => {
      said.textContent = words ? `“${words}”` : "";
      if (words && await deliver(words)) s.close();
    },
  });
}
