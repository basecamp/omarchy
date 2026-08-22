pragma Singleton
import QtQuick
import Quickshell

// Semantic UI token layer for Project Ultimate. This is the vocabulary every
// first-party shell surface is expected to consume instead of raw palette
// roles or arbitrary hex values, so the whole desktop looks designed rather
// than themed (see PRODUCT_DOCTRINE.md and docs/design-tokens.md).
//
// Tokens are derived from the existing Color (theme palette) and Style
// (structure) singletons, so themes keep working unchanged: a theme swap
// re-derives every semantic token automatically. Later phases can pin any
// token from theme/shell.toml via the same override machinery Style uses;
// nothing consumes Tokens until that lands, which is why this layer starts
// as pure derivation.
//
//   Tokens.surface.canvas   desktop wallpaper backdrop / main application background
//   Tokens.surface.base     windows, settings pages, cards
//   Tokens.surface.raised   raised cards, hover-elevated rows
//   Tokens.surface.glass    Start, taskbar, transient menus, flyouts, toasts
//   Tokens.surface.overlay  scrims and modal overlays
//
//   Tokens.text.primary / secondary / disabled
//   Tokens.accent.primary / hover / pressed
//   Tokens.border.subtle / strong
//
//   Tokens.state.success / warning / danger / info
//     danger maps to the theme's urgent role and info to accent today;
//     success and warning reuse accent/urgent until the theme schema gains
//     dedicated state colors in the design-system phase.
//
//   Tokens.radius.small / medium / large
//     derived from Style.cornerRadius (which mirrors Hyprland's
//     decoration:rounding): tiny controls, standard surfaces, major panels.
//
//   Tokens.motion.fast / normal
//     hover ~100 ms; panels/menus ~200 ms. Motion communicates causality;
//     reduced-motion handling arrives with the accessibility phase.
QtObject {
  id: root

  // ------------------------------------------------------------- surfaces
  readonly property QtObject surface: QtObject {
    property color canvas: Color.background
    property color base: Qt.lighter(Color.background, 1.08)
    property color raised: Qt.lighter(Color.background, 1.16)
    property color glass: Util.alpha(Color.background, 0.82)
    property color overlay: Util.alpha(Color.background, 0.6)
  }

  // ----------------------------------------------------------------- text
  readonly property QtObject text: QtObject {
    property color primary: Color.foreground
    property color secondary: Color.muted
    property color disabled: Util.alpha(Color.foreground, 0.4)
  }

  // --------------------------------------------------------------- accent
  readonly property QtObject accent: QtObject {
    property color primary: Color.accent
    property color hover: Qt.lighter(Color.accent, 1.1)
    property color pressed: Qt.darker(Color.accent, 1.1)
  }

  // --------------------------------------------------------------- border
  readonly property QtObject border: QtObject {
    property color subtle: Util.alpha(Color.foreground, 0.15)
    property color strong: Util.alpha(Color.foreground, 0.3)
  }

  // ---------------------------------------------------------------- state
  readonly property QtObject state: QtObject {
    property color success: Color.accent
    property color warning: Color.urgent
    property color danger: Color.urgent
    property color info: Color.accent
  }

  // --------------------------------------------------------------- radius
  readonly property QtObject radius: QtObject {
    property int small: Math.max(4, Math.round(Style.cornerRadius * 0.5))
    property int medium: Style.cornerRadius
    property int large: Math.round(Style.cornerRadius * 1.5)
  }

  // --------------------------------------------------------------- motion
  readonly property QtObject motion: QtObject {
    property int fast: 100
    property int normal: 200
  }
}
