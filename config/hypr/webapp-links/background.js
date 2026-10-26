// Loaded into every web app's Chromium profile (webapp-add: --load-extension). Links to other sites go to the default
// browser through the native host (hypr/scripts/webapp-links-host), which says whether it opened one: not when the
// default browser is Chromium itself. Then Chromium's own way stands: a tab in this profile's browser window.
"use strict";

const HOST = "sh.nightdrive.webapp_links";

function openOutside(url) {
  return new Promise(resolve => {
    chrome.runtime.sendNativeMessage(HOST, { url }, reply => {
      resolve(!chrome.runtime.lastError && !!reply && reply.opened === true);   // no host (removed, broken): Chromium's way
    });
  });
}

async function openInChromium(url) {
  const [win] = await chrome.windows.getAll({ windowTypes: ["normal"] });
  if (win) {
    await chrome.tabs.create({ windowId: win.id, url });
    await chrome.windows.update(win.id, { focused: true });
  } else {
    await chrome.windows.create({ url });
  }
}

// content.js: a click on a link to another site that would open a new tab or window, kept from opening
chrome.runtime.onMessage.addListener(msg => {
  if (typeof msg.open !== "string") return;
  openOutside(msg.open).then(opened => { if (!opened) openInChromium(msg.open); });
});

// Links content.js didn't see (a page's window.open, a link inside a frame): the new tab is already there, in a browser
// window. Only from an app window, and not a popup (a login's window.open with a size): that stays as the site expects.
chrome.webNavigation.onCreatedNavigationTarget.addListener(async d => {
  try {
    const [src, tab] = await Promise.all([chrome.tabs.get(d.sourceTabId), chrome.tabs.get(d.tabId)]);
    const [srcWin, win] = await Promise.all([chrome.windows.get(src.windowId), chrome.windows.get(tab.windowId)]);
    if (srcWin.type !== "app" || win.type !== "normal") return;
    const url = new URL(d.url);
    if (!/^https?:$/.test(url.protocol) || url.origin === new URL(src.url).origin) return;
    if (await openOutside(url.href)) await chrome.tabs.remove(d.tabId);
  } catch (e) {
    // a tab closed meanwhile, or a URL that isn't one: leave it be
  }
});
