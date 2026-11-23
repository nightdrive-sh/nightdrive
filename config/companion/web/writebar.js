// The session view's field for writing (#3370): under the conversation, not a box over it, so the
// conversation scrolls while you write and you see what you answer. Write opens it (and a tap on Answer: talking is
// the button's, a tap is for the keyboard) in place of the view's buttons (app.css), × or Esc gives them back; it
// stays open after Send for the next words.
// It is an element of its own beside the footer, which frame() redraws with every state: the words being written
// survive that. Send goes the way every other way of sending into a session goes (compose.js send: your words show
// at once at the end of the conversation, faded, pending.js); words that don't get there come back into the field.
import { icon } from "./icons.js";
import { send } from "./compose.js";

const MAX_LINES = 8;       // then it scrolls inside: the conversation keeps most of a phone's screen

// The bar inside the view's element el, for session id. atEnd() and toEnd() keep the conversation's end in sight
// as the field opens, grows and shrinks. Returns { open, shown(visible) }.
export function writeBar(el, id, { atEnd, toEnd }) {
  const bar = document.createElement("div");
  bar.className = "wbar";
  bar.hidden = true;
  // One row in place of the view's buttons, as a chat's: × back to them, the words, Send at the words' last line
  bar.innerHTML = `<button class="close" aria-label="Close the field">${icon("x", 18)}</button>
    <textarea rows="1" placeholder="Write it" enterkeyhint="enter" aria-label="Write to the session"></textarea>
    <button class="go" aria-label="Send">${icon("send", 18)}</button>`;
  el.querySelector(".dfoot").before(bar);
  const area = bar.querySelector("textarea");
  let opened = false, allowed = true;

  // As tall as its words, up to MAX_LINES; the conversation keeps its end in sight while it grows
  const fit = () => {
    const end = atEnd();
    area.style.height = "0px";      // then scrollHeight is the words' own, not the box's
    // border-box: its height is the words, their padding and the border (scrollHeight has the first two)
    const st = getComputedStyle(area);
    const edge = area.offsetHeight - area.clientHeight;
    const most = (parseFloat(st.lineHeight) || 22) * MAX_LINES + parseFloat(st.paddingTop) + parseFloat(st.paddingBottom) + edge;
    area.style.height = `${Math.min(area.scrollHeight + edge, most)}px`;
    if (end) toEnd();
  };
  const show = () => {
    const end = atEnd();
    bar.hidden = !(opened && allowed);
    el.classList.toggle("writing", !bar.hidden);
    if (end) toEnd();
  };
  const open = () => {
    opened = true;
    show();
    fit();
    area.focus();
  };
  const close = () => {
    opened = false;
    area.blur();
    show();
  };
  const go = async () => {
    const words = area.value.trim();
    if (!words) return area.focus();
    area.value = "";
    fit();
    area.focus();          // the keyboard stays up for the next words
    // Not there: back in the field, unless something new was written meanwhile (Send again is at the end too)
    if (!await send(id, words) && !area.value.trim()) { area.value = words; fit(); }
  };

  area.addEventListener("input", fit);
  area.addEventListener("keydown", e => {
    // ⌘ or Ctrl + Enter sends (an iPad's keyboard); Enter alone is a new line, as on the phone's keyboard
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); go(); }
    // Esc closes the field, not the view under it (detail.js closes the view on Esc)
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); }
  });
  bar.querySelector(".go").addEventListener("click", go);
  // Pressed, the button would take the focus and the keyboard would drop between words: the field keeps it
  bar.querySelector(".go").addEventListener("pointerdown", e => e.preventDefault());
  bar.querySelector(".close").addEventListener("click", close);
  // The bar's clicks are its own: the view's handler (detail.js) takes .close as closing the whole view
  bar.addEventListener("click", e => e.stopPropagation());

  return {
    open,
    // Hidden while a question or a permission is what the session waits on (its answers are the footer's); the
    // words written stay in it
    shown(visible) {
      if (visible === allowed) return;
      allowed = visible;
      show();
    },
  };
}
