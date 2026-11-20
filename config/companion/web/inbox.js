// Nightdrive Inbox on the page (#3187, protocol.md › Inbox): the messages the computer's Inbox keeps, over the whole
// screen. Wide (an iPad on its side) the list and the message open side by side; narrower (a phone, an iPad upright)
// the list, and a message over it with Back. Opening a message marks it read, as the window does; Mark unread and
// Archive are under it. The top bar's mailbox (inboxButton) opens the view and shows how many are unread.
// The view and an open message are steps in the browser's history, so Back and the edge swipe (swipe.js) go back one.
// The state's inbox.stamp changes with any message: the list (and the open message) are read again then.
import { esc, get, post, store, subscribe, toast } from "./api.js";
import { icon } from "./icons.js";
import { markdown } from "./markdown.js";
import { edgeSwipe } from "./swipe.js";

const WIDE = "(min-width: 900px) and (orientation: landscape)";
const DAY_MS = 864e5;
let view = null;     // { el, list, msg: the one open, whole, or null, stamp: the list's }

// The top bar's button: the mailbox, the unread count on it
export function inboxButton(state) {
  const n = state?.inbox?.unread || 0;
  return `<button class="inbox-btn" aria-label="Inbox${n ? `, ${n} unread` : ""}">${icon("inbox", 20)}
    ${n ? `<b>${n > 99 ? "99+" : n}</b>` : ""}</button>`;
}

const wide = () => matchMedia(WIDE).matches;

// "13:31" today, "Yesterday", "Thu" this week, else "19 Nov"
function when(iso) {
  const t = new Date(iso);
  if (isNaN(t)) return "";
  const today = new Date(); today.setHours(0, 0, 0, 0);
  if (t >= today) return t.toTimeString().slice(0, 5);
  if (t >= today - DAY_MS) return "Yesterday";
  if (t >= today - 6 * DAY_MS) return t.toLocaleDateString("en-GB", { weekday: "short" });
  return t.toLocaleDateString("en-GB", { day: "numeric", month: "short" });
}

// " · #3187" unless the sender's name has it already (a session named for its task)
const task = (m, who) => m.task && !String(who || "").includes(`#${m.task}`) ? ` · #${esc(m.task)}` : "";

// The message's own line: the day and time in full
function stamp(iso) {
  const t = new Date(iso);
  return isNaN(t) ? "" : t.toLocaleString("en-GB", { weekday: "short", day: "numeric", month: "short",
                                                     hour: "2-digit", minute: "2-digit" });
}

export function openInbox() {
  if (view) return;
  history.pushState({ inbox: true }, "");
  const el = document.createElement("div");
  el.className = "detail inbox";
  el.setAttribute("role", "dialog");
  el.innerHTML = `<header class="dhead"><button class="close" aria-label="Close">${icon("x", 18)}</button>
    <div class="who"><b>Inbox</b><span class="count"></span></div></header>
    <div class="ibox"><nav class="ilist" aria-label="Messages"></nav><article class="imsg"></article></div>`;
  document.body.append(el);
  view = { el, list: null, msg: null, stamp: null };
  el.addEventListener("click", click);
  edgeSwipe(el, back);
  load();
}

// Back: from a message to the list on a narrow screen, else out of the view
function back() {
  if (history.state?.inbox) history.back(); else shut();
}
addEventListener("popstate", () => {
  if (!view) return;
  if (!history.state?.inbox) return shut();
  if (!history.state.msg && !wide() && view.msg) { view.msg = null; renderList(); renderMsg(); }
});
if (history.state?.inbox) history.replaceState(null, "");    // a reload opens the page, not the view

function shut() {
  if (!view) return;
  view.el.remove();
  view = null;
}

async function load() {
  if (!view) return;
  const v = view;
  try {
    const got = await get("/api/inbox");
    if (view !== v) return;
    if (got.error) throw new Error(got.error);
    v.list = got;
    v.stamp = store.state?.inbox?.stamp;
  } catch (e) {
    v.list = { messages: [], error: e.message || "No connection to the computer" };
  }
  renderList();
  // Nothing opens by itself, wide either: opening marks a message read, and only a look should
  if (v.msg) open(v.msg.id, { step: false });     // it may have changed too (a session added to it)
  else renderMsg();
}

function renderList() {
  const { list, msg, el } = view;
  const unread = list?.unread || 0;
  el.querySelector(".count").textContent = list?.error ? "" : unread ? `${unread} unread` : "All read";
  const rows = list?.messages || [];
  el.querySelector(".ilist").innerHTML = list?.error ? `<div class="empty">${esc(list.error)}</div>`
    : rows.length ? rows.map(m => `
      <button class="irow${m.read ? "" : " unread"}${msg?.id === m.id ? " on" : ""}" data-id="${esc(m.id)}">
        <i class="dot"></i>
        <span class="ititle">${esc(m.title)}</span>
        <span class="iwhen">${esc(when(m.at))}</span>
        <span class="ifrom">${esc(m.sender?.short || "")}${task(m, m.sender?.short)}</span>
        ${m.attachments ? `<span class="ifiles">${icon("paperclip", 13)}${esc(m.attachments)}</span>` : ""}
      </button>`).join("")
    : '<div class="empty">Nothing in the Inbox</div>';
}

function files(list) {
  const pics = list.filter(f => f.type.startsWith("image/"));
  const rest = list.filter(f => !f.type.startsWith("image/"));
  return (pics.length ? `<div class="ipics">${pics.map(f => `<a href="${esc(f.url)}" target="_blank" rel="noopener">
      <img src="${esc(f.url)}" alt="${esc(f.name)}" loading="lazy"></a>`).join("")}</div>` : "") +
    (rest.length ? `<div class="iattach">${rest.map(f => `<a class="pill quiet" href="${esc(f.url)}" target="_blank"
      rel="noopener">${icon("paperclip", 15)}<span>${esc(f.name)}</span></a>`).join("")}</div>` : "");
}

function renderMsg(top = true) {
  const { el, msg } = view;
  el.classList.toggle("reading", !!msg);
  const pane = el.querySelector(".imsg");
  if (!msg) {
    pane.innerHTML = view.list?.messages?.length ? '<div class="empty">Pick a message</div>' : "";
    return;
  }
  const scroll = pane.querySelector(".ibody")?.scrollTop || 0;
  pane.innerHTML = `
    <div class="ihead">
      <button class="close iback" aria-label="Back to the list">${icon("chevron-left", 20)}</button>
      <div class="who"><b>${esc(msg.title)}</b>
        <span>${esc(msg.sender?.label || "")} · ${esc(stamp(msg.at))}${task(msg, msg.sender?.label)}</span></div>
    </div>
    <div class="ibody">
      ${msg.body ? `<div class="md">${markdown(msg.body)}</div>` : ""}
      ${files(msg.attachments || [])}
      ${msg.actions ? `<div class="meta">${msg.actions === 1 ? "A button" : `${esc(msg.actions)} buttons`} in the Inbox on the computer</div>` : ""}
    </div>
    <div class="row ifoot">
      <button class="pill" data-do="${msg.read ? "unread" : "read"}">${icon("mail", 16)}<span>${msg.read ? "Mark unread" : "Mark read"}</span></button>
      <span class="spacer"></span>
      <button class="pill main" data-do="archive">${icon("archive", 16)}<span>Archive</span></button>
    </div>`;
  if (!top) pane.querySelector(".ibody").scrollTop = scroll;
}

// The message whole; opening it marks it read (on the computer too). step: a step in the history, for Back (narrow)
async function open(id, { step = true } = {}) {
  const v = view;
  let msg;
  try {
    msg = await get(`/api/inbox/${encodeURIComponent(id)}`);
  } catch {
    return toast("No connection to the computer", true);
  }
  if (view !== v) return;
  if (msg.error) {           // archived or deleted meanwhile, elsewhere
    if (v.msg?.id === id) { v.msg = null; renderMsg(); }
    return toast(msg.error, true);
  }
  const was = v.msg?.id;
  v.msg = msg;
  if (step && !wide() && !history.state?.msg) history.pushState({ inbox: true, msg: id }, "");
  if (!msg.read) {
    post(`/api/inbox/${encodeURIComponent(id)}/read`, undefined, { quiet: true });
    msg.read = true;
    const row = v.list?.messages?.find(m => m.id === id);
    if (row && !row.read) { row.read = true; v.list.unread = Math.max(0, (v.list.unread || 1) - 1); }
  }
  renderList();
  renderMsg(was !== id);
}

async function act(what) {
  const v = view, msg = v.msg;
  if (!(await post(`/api/inbox/${encodeURIComponent(msg.id)}/${what}`))) return;
  if (view !== v) return;
  if (what === "archive") {
    toast("Archived");
    v.msg = null;
    if (history.state?.msg) history.back();
    return load();
  }
  msg.read = what === "read";
  const row = v.list?.messages?.find(m => m.id === msg.id);
  if (row) row.read = msg.read;
  v.list.unread = (v.list.messages || []).filter(m => !m.read).length;
  renderList();
  renderMsg(false);
}

function click(e) {
  if (e.target.closest(".iback")) return back();
  if (e.target.closest(".dhead .close")) return history.state?.msg ? history.go(-2) : back();
  const row = e.target.closest(".irow");
  if (row) return open(row.dataset.id);
  const b = e.target.closest("button[data-do]");
  if (b) act(b.dataset.do);
}

// A message came, was read or archived anywhere (the window, Claude, another device): read the list again
subscribe(state => {
  if (view && state?.inbox?.stamp && view.stamp && state.inbox.stamp !== view.stamp) {
    view.stamp = state.inbox.stamp;
    load();
  }
});
