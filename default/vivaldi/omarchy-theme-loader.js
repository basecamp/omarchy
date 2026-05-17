(() => {
  let last = '';
  const refresh = async () => {
    try {
      const colors = await (await fetch('style/omarchy.csv', { cache: 'no-store' })).text();

      if (colors === last || !/^#[a-f\d]{6}(,#[a-f\d]{6}){2}$/i.test(colors)) return;
      const [bg, fg, accent] = colors.split(',');

      document.getElementById('omarchy-theme').textContent = `
      #browser {
        --colorBg: ${bg} !important;
        --colorFg: ${fg} !important;
        --colorAccentBg: ${bg} !important;
        --colorAccentFg: ${fg} !important;
        --colorHighlightBg: color-mix(in srgb, ${accent}, ${bg} 25%) !important;
        --colorHighlightFg: ${fg} !important;
        --colorFgIntense: ${fg} !important; /* address bar font */
        --colorBgLightIntense: color-mix(in srgb, ${bg}, ${fg} 10%) !important;
      }`;
      last = colors;
    } catch (e) {
      console.error(e);
    }
  };
  refresh();
  setInterval(refresh, 2000);
})();
