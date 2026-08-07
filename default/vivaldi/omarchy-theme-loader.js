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

  const syncNativeTheme = (bg, fg, accent, lighterBg, onDone) => {
    try {
      const prefs = window.vivaldi && window.vivaldi.prefs;
      if (!prefs || typeof prefs.get !== 'function' || typeof prefs.set !== 'function') return;

      const colors = {
        colorBg: bg,
        colorFg: fg,
        colorAccentBg: lighterBg,
        colorHighlightBg: accent,
        colorWindowBg: bg
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
        alpha: 1,
        backgroundImage: '',
        backgroundPosition: 'stretch',
        backgroundSource: '',
        blur: 0,
        colorAccentBg: accent,
        colorBg: bg,
        colorFg: fg,
        colorAccentBg: lighterBg,
        colorHighlightBg: accent,
        colorPosition: 'unified',
        colorWindowBg: bg,
        contrast: 0,
        dimBlurred: false,
        preferSystemAccent: false,
        radius: 4,
        simpleScrollbar: true,
        transparencyTabBar: false,
        transparencyTabs: false
      };

      prefs.get('vivaldi.themes.user').then(function (result) {
        const list = (result && result.value) || [];
        let found = false;
        const themes = list.map(function (t) {
          if (t && t.id === 'Omarchy') {
            found = true;
            return Object.assign({}, t, colors);
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

  const refresh = async () => {
    try {
      const raw = await (await fetch('style/omarchy.csv', { cache: 'no-store' })).text();
      if (!/^#[a-f\d]{6}(,#[a-f\d]{6}){3}$/i.test(raw)) return;
      loggedError = false;
      const [bg, fg, accent, lighterBg] = raw.split(',');
      if (raw !== synced) {
        syncNativeTheme(bg, fg, accent, lighterBg, function () { synced = raw });
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
