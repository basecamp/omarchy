(() => {
  let synced = '';

  const nudgeCurrentTheme = (prefs, done) => {
    const setCurrent = function(value, next) {
      const set = prefs.set({ path: 'vivaldi.themes.current', value: value });
      if (set && typeof set.then === 'function') set.then(next, next);
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
    }).catch(function () { setCurrent('Omarchy', done); });
  };

  const syncNativeTheme = (bg, fg, accent, onDone) => {
    try {
      const prefs = window.vivaldi && window.vivaldi.prefs;
      if (!prefs || typeof prefs.get !== 'function' || typeof prefs.set !== 'function') return;

      const colors = {
        colorBg: bg,
        colorFg: fg,
        colorAccentBg: accent,
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
        prefs.set({ path: 'vivaldi.themes.user', value: themes });
        nudgeCurrentTheme(prefs, done);
      }).catch(done);
    } catch (e) {
      if (onDone) onDone();
    }
  };

  const refresh = async () => {
    try {
      const raw = await (await fetch('style/omarchy.csv', { cache: 'no-store' })).text();
      if (!/^#[a-f\d]{6}(,#[a-f\d]{6}){2}$/i.test(raw)) return;
      const [bg, fg, accent] = raw.split(',');
      if (raw !== synced) {
        syncNativeTheme(bg, fg, accent, function () { synced = raw });
      }
    } catch (e) {
      console.error(e);
    }
  };

  refresh();
  setInterval(refresh, 2000);
})();
