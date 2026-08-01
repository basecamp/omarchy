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
  const owners = new Set();

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
    let onchange = null;
    let proxy = null;

    function captureFrom(options) {
      return typeof options === "boolean" ? options : !!options?.capture;
    }

    function has(cb, capture) {
      for (const e of listeners)
        if (e.owner === owner && e.cb === cb && e.capture === capture) return true;
      return false;
    }

    function add(cb, options = false) {
      // Native listeners dedupe on identity; adding twice must not fire twice.
      const capture = captureFrom(options);
      if (
        (typeof cb !== "function" && typeof cb?.handleEvent !== "function") ||
        options?.signal?.aborted ||
        has(cb, capture)
      )
        return;
      const entry = {
        owner,
        cb,
        capture,
        once: !!options?.once,
        signal: options?.signal,
        wantsDark,
        wantsLight,
      };
      listeners.add(entry);
      if (entry.signal) {
        entry.abort = () => listeners.delete(entry);
        entry.signal.addEventListener("abort", entry.abort, { once: true });
      }
    }

    function remove(cb, options = false) {
      const capture = captureFrom(options);
      for (const e of listeners) {
        if (e.owner !== owner || e.cb !== cb || e.capture !== capture) continue;
        listeners.delete(e);
        if (e.signal) e.signal.removeEventListener("abort", e.abort);
      }
    }

    proxy = new Proxy(target, {
      get(_t, prop) {
        if (prop === "matches") {
          if (wantsDark) return isDark;
          if (wantsLight) return !isDark;
          return target.matches;
        }
        if (prop === "media") return query;
        if (prop === "onchange") return onchange;
        if (prop === "addEventListener") {
          return (evt, cb, options) => {
            if (evt === "change") add(cb, options);
          };
        }
        if (prop === "removeEventListener") {
          return (evt, cb, options) => {
            if (evt === "change") remove(cb, options);
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
      set(_t, prop, value) {
        if (prop === "onchange") {
          onchange = typeof value === "function" ? value : null;
          if (onchange) owners.add(owner);
          else owners.delete(owner);
          return true;
        }
        return Reflect.set(target, prop, value);
      },
    });
    owner.proxy = proxy;
    owner.onchange = () => onchange;
    owner.wantsDark = wantsDark;
    owner.wantsLight = wantsLight;
    return proxy;
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
    for (const entry of listeners) {
      const { owner, cb, wantsDark, wantsLight } = entry;
      const matches = wantsDark ? isDark : wantsLight ? !isDark : false;
      const media = wantsDark
        ? "(prefers-color-scheme: dark)"
        : wantsLight
        ? "(prefers-color-scheme: light)"
        : "";
      try {
        if (entry.once) listeners.delete(entry);
        if (entry.signal) entry.signal.removeEventListener("abort", entry.abort);
        // Shaped like a MediaQueryListEvent; apps read .matches. The legacy
        // addListener callback takes the same argument, so there is nothing to
        // branch on here.
        const event = { matches, media, target: owner.proxy, currentTarget: owner.proxy };
        if (typeof cb === "function") cb.call(owner.proxy, event);
        else cb.handleEvent(event);
      } catch (_) {}
    }
    for (const owner of owners) {
      const cb = owner.onchange();
      if (!cb) continue;
      const matches = owner.wantsDark ? isDark : owner.wantsLight ? !isDark : false;
      const media = owner.wantsDark
        ? "(prefers-color-scheme: dark)"
        : owner.wantsLight
        ? "(prefers-color-scheme: light)"
        : "";
      try {
        cb.call(owner.proxy, {
          matches,
          media,
          target: owner.proxy,
          currentTarget: owner.proxy,
        });
      } catch (_) {}
    }
  });
})();
