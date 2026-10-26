// A click on a link that would open another site in a new tab or window: the app window would put it in Chromium. Here
// it goes to background.js instead, which hands it to the default browser. Only after the page's own handlers (bubble
// phase, defaultPrevented): a site that handles the click itself (often with window.open) is left to it, and
// background.js catches that new window. A link that stays in the window (a login's redirect) is never touched.
"use strict";

function newWindowClick(e, a) {
  if (e.type === "auxclick") return e.button === 1;              // middle click: a new tab
  if (e.button !== 0) return false;
  if (e.ctrlKey || e.metaKey || e.shiftKey) return true;
  const target = a.target || (document.querySelector("base[target]") || {}).target || "";
  return target !== "" && !["_self", "_top", "_parent"].includes(target.toLowerCase());
}

function onClick(e) {
  if (e.defaultPrevented) return;
  const a = e.target instanceof Element ? e.target.closest("a[href]") : null;
  if (!a || a.hasAttribute("download") || !newWindowClick(e, a)) return;
  let url;
  try { url = new URL(a.href, location.href); } catch (err) { return; }
  if (!/^https?:$/.test(url.protocol) || url.origin === location.origin) return;   // the app's own pages stay in it
  e.preventDefault();
  e.stopImmediatePropagation();
  chrome.runtime.sendMessage({ open: url.href });
}

window.addEventListener("click", onClick);
window.addEventListener("auxclick", onClick);
