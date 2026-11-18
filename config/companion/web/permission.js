// A permission request whole, before its Allow (#3137): Review on a tile or in the session's own view opens a box with
// every key of what Claude Code would run (the file, the text it takes out and puts in, an MCP tool's input), in full
// and nothing cut, from GET /api/sessions/ID/permission. A character that wouldn't show comes written out as ⟨U+XXXX⟩
// (lib/permission.py). Allow there answers that request and no other: it names the request it showed, and the box
// closes when the session no longer asks it (answered on the computer, or it asks something else).
import { esc, get, post, sheet, store, subscribe, toast } from "./api.js";
import { icon } from "./icons.js";

function session(id) {
  return store.state?.sessions?.find(x => x.id === id);
}

function body(p) {
  const hidden = p.fields.reduce((n, f) => n + f.hidden, 0);
  const rows = p.fields.map(f => `<div class="pfield"><span class="pkey">${esc(f.key)}</span>
      <pre class="pval">${esc(f.text) || '<span class="pnone">(empty)</span>'}</pre></div>`).join("");
  return `${hidden ? `<div class="pwarn">${icon("shield", 15)}${hidden} character${hidden > 1 ? "s" : ""} that
      wouldn't show, written out as ⟨U+…⟩.</div>` : ""}
    <div class="pfields">${rows || '<div class="pnone">No input</div>'}</div>`;
}

export async function openPermission(id) {
  const s = session(id);
  const request = s?.permission?.request;
  if (!request) return;
  let p;
  try { p = await get(`/api/sessions/${encodeURIComponent(id)}/permission`); } catch { p = null; }
  if (!p?.fields) return toast(p?.error || "No connection to the computer", true);
  // the state may have moved on while it loaded: show only the request the tile was showing
  if (p.request !== request || session(id)?.permission?.request !== request) return toast("It asks something else now", true);
  const box = sheet(`<div class="row"><span class="sec">${esc(s.name || s.project)}</span><span class="spacer"></span>
      <button class="close" aria-label="Close">${icon("x", 18)}</button></div>
    <div class="ptool">${esc(p.tool)}${s.project ? ` <span>· ${esc(s.project)}</span>` : ""}</div>
    ${body(p)}
    <div class="row"><span class="spacer"></span>
      <button class="pill" data-answer="deny">Deny</button>
      <button class="pill main" data-answer="allow">${icon("check", 16, 2.2)}Allow</button></div>`,
    { cls: "permission", onClose: () => stop() });
  box.el.querySelector(".close").onclick = box.close;
  box.el.addEventListener("click", async e => {
    const b = e.target.closest("button[data-answer]");
    if (!b) return;
    b.disabled = true;
    const ok = await post(`/api/sessions/${encodeURIComponent(id)}/${b.dataset.answer}`, { request });
    if (ok) box.close(); else b.disabled = false;
  });
  const stop = subscribe(state => {
    if (state?.sessions?.find(x => x.id === id)?.permission?.request !== request) box.close();
  });
}
