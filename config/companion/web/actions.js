// The six action slots, in two columns: a tap runs one, holding one (or a tap on an empty one) chooses what it does: one of the
// server's presets, or a command of your own (it runs on the computer, as you).
import { esc, get, post, press, sheet, store, subscribe, toast } from "./api.js";
import { icon } from "./icons.js";

const list = document.querySelector(".actions .slots");
const SLOTS = 6;      // control.SLOTS: until the state comes
let presets = null;

function render(state) {
  const slots = state?.actions || Array(SLOTS).fill(null);
  const sig = JSON.stringify(slots);
  if (list.dataset.sig === sig) return;
  list.dataset.sig = sig;
  list.innerHTML = slots.map((a, n) => a
    ? `<button class="slot set" data-n="${n}" aria-label="${esc(a.label)}"><span class="key">${n + 1}</span>
         <span class="what"><span class="ic">${icon(a.icon, 16)}</span><span class="label">${esc(a.label)}</span></span></button>`
    : `<button class="slot" data-n="${n}" aria-label="Add an action"><span class="key">${n + 1}</span>
         <span class="what"><span class="ic">${icon("plus", 16)}</span><span class="label">Add action</span></span></button>`
  ).join("");
  for (const el of list.querySelectorAll(".slot")) {
    const n = Number(el.dataset.n);
    const a = slots[n];
    press(el, () => a ? run(n, el) : choose(n), () => choose(n));
  }
}

async function run(n, el) {
  if (await post(`/api/actions/${n}/run`)) {
    el.classList.add("done");
    setTimeout(() => el.classList.remove("done"), 700);
    if (store.state?.demo) toast("Demo: nothing runs on the desktop");
  }
}

async function choose(n) {
  presets ??= await get("/api/presets").catch(() => []);
  const now = store.state?.actions?.[n];
  const s = sheet(`
    <div class="row"><span class="sec">Action ${n + 1}</span></div>
    <div class="choices">${presets.map(p => `<button class="choice ${now?.preset === p.id ? "on" : ""}" data-preset="${esc(p.id)}">
      ${icon(p.icon)}${esc(p.label)}</button>`).join("")}</div>
    <span class="sec" style="margin-top:6px">Your own</span>
    <input type="text" class="label" placeholder="Label" maxlength="40" value="${now?.custom ? esc(now.label) : ""}">
    <input type="text" class="command" placeholder="Command, e.g. hyprctl dispatch …" autocapitalize="off" autocorrect="off" spellcheck="false">
    <div class="row">${now ? '<button class="pill clear">Empty it</button>' : ""}<span class="spacer"></span>
      <button class="pill cancel">Cancel</button><button class="pill main save" style="flex:0 1 auto">Save</button></div>`);
  const save = async body => {
    if (await post(`/api/actions/${n}`, body)) s.close();
  };
  s.el.querySelectorAll("[data-preset]").forEach(b => b.onclick = () => save({ preset: b.dataset.preset }));
  s.el.querySelector(".cancel").onclick = s.close;
  s.el.querySelector(".clear")?.addEventListener("click", () => save(null));
  s.el.querySelector(".save").onclick = () => {
    const command = s.el.querySelector(".command").value.trim();
    if (!command) return toast(now?.custom ? "Write the command again to change it" : "Pick one above or write a command", true);
    save({ label: s.el.querySelector(".label").value.trim() || "Action", icon: "zap", command });
  };
}

subscribe(render);
