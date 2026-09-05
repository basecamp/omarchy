(() => {
  let synced = '';
  let loggedError = false;

  const nudgeCurrentTheme = (prefs, done) => {
    const setCurrent = function(value, next) {
      const set = prefs.set({ path: 'vivaldi.themes.current', value: value });
      if (set && typeof set.then === 'function') set.then(next, function () {});
      else next();
    };
    prefs.get('vivaldi.themes.current').then(function (result) {
      const current = (result && result.value) || '';
      if (current === 'Omarchy') {
        // Force a change so the theme handler re-applies the updated colors.
        setCurrent('Vivaldi2', function () { setCurrent('Omarchy', done); });
      } else {
        setCurrent('Omarchy', done);
      }
    }).catch(function () {});
  };

  const syncNativeTheme = (bg, fg, accent, lighterBg, radius, dimBlurred, blur, contrast, onDone) => {
    try {
      const prefs = window.vivaldi && window.vivaldi.prefs;
      if (!prefs || typeof prefs.get !== 'function' || typeof prefs.set !== 'function') return;

      // Apply the full Omarchy theme (colors plus Hyprland-derived appearance)
      // from the channel so updates land in the running browser.
      const appearance = {
        colorBg: bg,
        colorFg: fg,
        colorAccentBg: lighterBg,
        colorHighlightBg: accent,
        colorWindowBg: bg,
        radius: radius,
        dimBlurred: dimBlurred,
        blur: blur,
        contrast: contrast
      };
      const done = function () { if (onDone) onDone() };

      const theme = {
        engineVersion: 1,
        version: 1,
        id: 'Omarchy',
        url: '',
        name: 'Omarchy',
        accentFromPage: false,
        accentOnWindow: true,
        accentSaturationLimit: 1,
        alpha: 0.92,
        backgroundImage: '',
        backgroundPosition: 'stretch',
        backgroundSource: '',
        blur: blur,
        colorAccentBg: lighterBg,
        colorBg: bg,
        colorFg: fg,
        colorHighlightBg: accent,
        colorPosition: 'frame',
        colorWindowBg: bg,
        contrast: contrast,
        dimBlurred: dimBlurred,
        preferSystemAccent: false,
        radius: radius,
        simpleScrollbar: true,
        transparencyTabBar: false,
        transparencyTabs: true
      };

      prefs.get('vivaldi.themes.user').then(function (result) {
        const list = (result && result.value) || [];
        let found = false;
        const themes = list.map(function (t) {
          if (t && t.id === 'Omarchy') {
            found = true;
            return Object.assign({}, t, appearance);
          }
          return t;
        });
        if (!found) themes.push(theme);
        // Wait for the write before switching the active theme, or the handler
        // would re-derive from stale (or missing) Omarchy colors.
        return Promise.resolve(prefs.set({ path: 'vivaldi.themes.user', value: themes })).then(function () {
          nudgeCurrentTheme(prefs, done);
        });
      }).catch(function () {
        // Leave synced unset so the next poll retries.
      });
    } catch (e) {
      // Leave synced unset so the next poll retries.
    }
  };

  const applyThemeCss = (bg, fg, accent, lighterBg, radius) => {
    const style = document.getElementById('omarchy-theme');
    if (!style) return;
    const mix = (a, b, p) => `color-mix(in srgb, ${a}, ${b} ${p})`;
    // Corner rounding is rendered from CSS custom properties, so inject them
    // alongside the colors to update corners live. Mirrors Vivaldi's own
    // derivation from the theme radius; -1 is "Disabled" (no rounding).
    const radiusPx = radius > -1 ? radius + 'px' : 0;
    style.textContent = `
      #browser {
        --colorBg: ${bg} !important;
        --colorBgLight: ${bg} !important;
        --colorBgIntense: ${mix(bg, 'white', '7%')} !important;
        --colorFg: ${fg} !important;
        --colorAccentBg: ${lighterBg} !important;
        --colorAccentFg: ${fg} !important;
        --colorHighlightBg: ${accent} !important;
        --colorHighlightFg: ${fg} !important;
        --colorWindowBg: ${bg} !important;
        --colorTabBar: ${lighterBg} !important;
        --radius: ${radiusPx} !important;
        --radiusRounded: ${radius > -1 ? '2px' : 0} !important;
        --radiusRoundedLess: ${radius > 0 ? (radius - 1) + 'px' : 0} !important;
        --radiusHalf: ${Math.round(radius / 2)}px !important;
        --radiusCap: ${Math.min(radius, 8)}px !important;
        --radiusRound: ${radius > -1 ? '100px' : 0} !important;
        --radiusWindow: 6px !important;
      }`;
  };

  const refresh = async () => {
    try {
      const text = await (await fetch('style/omarchy.json', { cache: 'no-store' })).text();
      const data = JSON.parse(text);
      const colors = data && data.colors || {};
      const bg = colors.bg;
      const fg = colors.fg;
      const accent = colors.accent;
      const lighterBg = colors.lighterBg;
      if (!/^#[a-f\d]{6}$/i.test(bg || '') || !/^#[a-f\d]{6}$/i.test(fg || '') ||
          !/^#[a-f\d]{6}$/i.test(accent || '') || !/^#[a-f\d]{6}$/i.test(lighterBg || '')) return;
      loggedError = false;
      // -1 is Vivaldi's "Disabled" corner rounding (Hyprland rounding 0); a
      // radius of 0 would still round controls, so it must not be clamped away.
      const rawRadius = Number(data.radius);
      const radius = Math.max(-1, Math.min(14, Math.round(isFinite(rawRadius) ? rawRadius : -1)));
      const dimBlurred = data.dimBlurred === true;
      const blur = Math.max(0, Math.min(10, Math.round(Number(data.blur) || 0)));
      const contrast = Math.max(-10, Math.min(20, Math.round(Number(data.contrast) || 0)));
      if (text !== synced) {
        applyThemeCss(bg, fg, accent, lighterBg, radius);
        syncNativeTheme(bg, fg, accent, lighterBg, radius, dimBlurred, blur, contrast, function () { synced = text });
      }
    } catch (e) {
      if (!loggedError) {
        loggedError = true;
        console.error(e);
      }
    }
  };

  refresh();
  setInterval(refresh, 2000);
})();
