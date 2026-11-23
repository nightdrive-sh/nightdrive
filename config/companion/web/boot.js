// Loads the page's code and never leaves half a page. One module that doesn't come through (a 502 from tailscale
// serve, a connection the iPad dropped) stops every import, and only index.html's static Dictate showed (#3080). So a
// file that fails loads the page once more, and when that fails too, the page says so with Reload (#3081).
// A classic script, not a module, so it runs when the modules don't. The second try is a reload, not a new import():
// a browser may keep a failed module for the page's life, and a reload starts its module map afresh.
// index.html styles the message itself (inline), as app.css may be the file that failed; it shows it on its own after
// a while when this file didn't come either.
(function () {
  "use strict";
  var RETRY = "retry";        // in the address while the page is on its second try
  var url = new URL(location.href);
  var retried = url.searchParams.has(RETRY);
  var root = document.documentElement;
  var done = false;

  function fail(what) {
    if (done) return;
    done = true;
    if (!retried) {
      url.searchParams.set(RETRY, "1");
      location.replace(url.href);
      return;
    }
    var detail = document.querySelector(".loadfail .what");
    if (detail) detail.textContent = what;
    root.classList.add("load-failed");
  }

  function loaded() {
    root.classList.add("ready");
    if (retried) {            // so the page's own Reload (a new version) starts with a try to spare again
      url.searchParams.delete(RETRY);
      history.replaceState(history.state, "", url.href);
    }
  }

  // Without app.css the page is unusable too. A stylesheet that failed has no sheet, or (Chromium, on an error
  // status) an empty one: none of the page's own is empty
  function failedSheet(link) {
    try {
      return !link.sheet || !link.sheet.cssRules.length;
    } catch (e) {
      return true;
    }
  }

  function checkStyles() {
    var links = document.querySelectorAll('link[rel="stylesheet"]');
    var bad = [];
    for (var i = 0; i < links.length; i++) if (failedSheet(links[i])) bad.push(links[i].getAttribute("href").replace(/^\//, ""));
    if (bad.length) fail("Didn't load: " + bad.join(", "));
  }

  import("/app.js").then(loaded, function (e) { fail((e && e.message) || "The page's code didn't load"); });
  if (document.readyState === "complete") checkStyles();
  else addEventListener("load", checkStyles);
})();
