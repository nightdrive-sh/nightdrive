// Loaded into every web app's Chromium profile (webapp-add: --load-extension). Links to other sites go to the default
// browser through the native host (hypr/scripts/webapp-links-host), which says whether it opened one: not when the
// default browser is Chromium itself. Then Chromium's own way stands: a tab in this profile's browser window.
// The number in this file's name: Chromium keeps an unpacked extension's service worker from its first start, through
// restarts and version changes, so a change here reaches the web apps only under a new name. Bump it (and
// manifest.json's service_worker and version) with every change.
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

// The app's own site, for telling its pages from others: app.slack.com and koodiklinikka.slack.com are both slack.com.
// No public suffix list here, so a short second label before a country code (co.uk, com.au) counts as part of the suffix.
function site(host) {
  if (/^[\d.]+$|^\[|^[^.]+$/.test(host)) return host;          // an IP address, or a name without dots (localhost)
  const parts = host.split(".");
  const n = parts.length > 2 && parts.at(-1).length === 2 && parts.at(-2).length <= 3 ? 3 : 2;
  return parts.slice(-n).join(".");
}

// A new tab's address: a page that opens a window empty (window.open("")) and then sets its location, or submits a
// form into it, makes the tab with about:blank first. Then wait for its first real navigation.
function firstUrl(tabId, url) {
  if (/^https?:/.test(url)) return Promise.resolve(url);
  return new Promise(resolve => {
    const done = u => { chrome.webNavigation.onBeforeNavigate.removeListener(seen); clearTimeout(timer); resolve(u); };
    const seen = d => { if (d.tabId === tabId && d.frameId === 0 && /^https?:/.test(d.url)) done(d.url); };
    const timer = setTimeout(() => done(null), 10000);
    chrome.webNavigation.onBeforeNavigate.addListener(seen);
  });
}

// Links content.js didn't see (a page's window.open, a form with a target, a link inside a frame): the new tab is
// already there, in this profile's browser window, which a web app should never leave behind. Another site goes to the
// default browser; the app's own site (Slack's sign-in to another workspace) stays with the app, in a window like
// its own. Only from an app window, and not a popup (a login's window.open with a size): that stays as the site expects.
chrome.webNavigation.onCreatedNavigationTarget.addListener(async d => {
  const urlNow = firstUrl(d.tabId, d.url);     // before any await, so a navigation right after isn't missed
  try {
    const [src, tab] = await Promise.all([chrome.tabs.get(d.sourceTabId), chrome.tabs.get(d.tabId)]);
    const [srcWin, win] = await Promise.all([chrome.windows.get(src.windowId), chrome.windows.get(tab.windowId)]);
    if (srcWin.type !== "app" || win.type !== "normal") return;
    const href = await urlNow;
    if (!href) return;
    const url = new URL(href);
    if (site(url.hostname) !== site(new URL(src.url).hostname)) {
      if (await openOutside(url.href)) await chrome.tabs.remove(d.tabId);
      return;
    }
    await chrome.windows.create({ tabId: d.tabId, type: "popup", width: srcWin.width, height: srcWin.height });
  } catch (e) {
    // a tab closed meanwhile, or a URL that isn't one: leave it be
  }
});
