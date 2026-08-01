// Omarchy web-app theming — prefers-color-scheme shim (app-agnostic).
//
// Runs in the page's MAIN world at document_start. Spoofs
// window.matchMedia('(prefers-color-scheme: ...)') so a web app's "sync with
// system" appearance follows the active Omarchy theme instead of the real OS
// setting. The engine (omarchy-runtime.js, isolated world) dispatches an
// `omarchy:set-color-scheme` event on every theme apply; we flip the spoofed
// value here and notify the app's registered media-query listeners, so an app
// on "System default" repaints live with no reload.

(function () {
  if (window.__omarchyPCSInstalled) return;
  window.__omarchyPCSInstalled = true;

  const orig = window.matchMedia.bind(window);
  let isDark = orig("(prefers-color-scheme: dark)").matches;
  const listeners = new Set();

  function makeProxy(query) {
    const wantsDark = /dark/i.test(query);
    const wantsLight = /light/i.test(query);
    const target = orig(query);
    // Registrations live in one shared Set, so they have to record which
    // MediaQueryList they came from. Without that, an app that hands the same
    // callback to both the dark and the light query and later detaches one
    // would silently detach the other too, and the query it still holds would
    // stop hearing theme changes. `addListener` is a legacy alias of
    // `addEventListener("change")`, so the two share a registration space and
    // either remover cancels either add.
    const owner = {};

    function has(cb) {
      for (const e of listeners) if (e.owner === owner && e.cb === cb) return true;
      return false;
    }

    function add(cb) {
      // Native listeners dedupe on identity; adding twice must not fire twice.
      if (typeof cb !== "function" || has(cb)) return;
      listeners.add({ owner, cb, wantsDark, wantsLight });
    }

    function remove(cb) {
      for (const e of listeners) if (e.owner === owner && e.cb === cb) listeners.delete(e);
    }

    return new Proxy(target, {
      get(_t, prop) {
        if (prop === "matches") {
          if (wantsDark) return isDark;
          if (wantsLight) return !isDark;
          return target.matches;
        }
        if (prop === "media") return query;
        if (prop === "addEventListener") {
          return (evt, cb) => {
            if (evt === "change") add(cb);
          };
        }
        if (prop === "removeEventListener") {
          return (evt, cb) => {
            if (evt === "change") remove(cb);
          };
        }
        if (prop === "addListener") {
          // deprecated API — single callback arg
          return (cb) => add(cb);
        }
        if (prop === "removeListener") {
          return (cb) => remove(cb);
        }
        const v = target[prop];
        return typeof v === "function" ? v.bind(target) : v;
      },
    });
  }

  window.matchMedia = function (query) {
    if (typeof query === "string" && /prefers-color-scheme/i.test(query)) {
      return makeProxy(query);
    }
    return orig(query);
  };

  document.addEventListener("omarchy:set-color-scheme", (ev) => {
    const next = !!(ev.detail && ev.detail.dark);
    if (next === isDark) return;
    isDark = next;
    for (const { cb, wantsDark, wantsLight } of listeners) {
      const matches = wantsDark ? isDark : wantsLight ? !isDark : false;
      const media = wantsDark
        ? "(prefers-color-scheme: dark)"
        : wantsLight
        ? "(prefers-color-scheme: light)"
        : "";
      try {
        // Shaped like a MediaQueryListEvent; apps read .matches. The legacy
        // addListener callback takes the same argument, so there is nothing to
        // branch on here.
        cb({ matches, media });
      } catch (_) {}
    }
  });
})();
