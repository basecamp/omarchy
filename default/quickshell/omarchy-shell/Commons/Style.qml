pragma Singleton
import QtQuick
import "." as Commons

// Noctalia compat shim. Sizing/spacing/typography tokens that plugins
// reference unconditionally. Real values picked to roughly match what
// Omarchy renders today — close enough that plugin layouts don't look
// jarring next to native widgets.
QtObject {
  id: root

  // Radii.
  readonly property real radiusXS: 2
  readonly property real radiusS:  3
  readonly property real radiusM:  4
  readonly property real radiusL:  6
  readonly property real radiusXL: 8
  readonly property real iRadiusXS: 2
  readonly property real iRadiusS:  3
  readonly property real iRadiusM:  4
  readonly property real iRadiusL:  6

  // Margins / paddings. Noctalia uses two parallel scales for margins (one
  // tighter, one looser); we map them to the same values.
  readonly property real marginXS:  2
  readonly property real marginS:   4
  readonly property real marginM:   6
  readonly property real marginL:   10
  readonly property real marginXL:  14
  readonly property real margin2XXS: 1
  readonly property real margin2XS: 2
  readonly property real margin2S:  3
  readonly property real margin2M:  5
  readonly property real margin2L:  8
  readonly property real margin2XL: 12

  // Border widths.
  readonly property real borderS: 1
  readonly property real borderM: 1
  readonly property real borderL: 2

  // Font sizes.
  readonly property real fontSizeXXS:  9
  readonly property real fontSizeXS:  10
  readonly property real fontSizeS:   11
  readonly property real fontSizeM:   12
  readonly property real fontSizeL:   14
  readonly property real fontSizeXL:  16
  readonly property real fontSizeXXL: 20
  readonly property real fontSizeXXXL: 24

  // Font weights.
  readonly property int fontWeightLight:    300
  readonly property int fontWeightRegular:  400
  readonly property int fontWeightMedium:   500
  readonly property int fontWeightSemiBold: 600
  readonly property int fontWeightBold:     700

  // Opacities.
  readonly property real opacityLight:  0.4
  readonly property real opacityMedium: 0.6
  readonly property real opacityHeavy:  0.8
  readonly property real opacityFull:   1.0

  // Animation durations (ms).
  readonly property int animationFast:    100
  readonly property int animationNormal:  160
  readonly property int animationSlow:    250
  readonly property int animationSlower:  400
  readonly property int animationSlowest: 600

  // Tooltip delay (ms).
  readonly property int tooltipDelay: 400

  // Capsule (bar pill) tokens. The Omarchy bar is flat, no capsule background,
  // so we route these to transparent + the foreground outline for visual hint.
  readonly property color capsuleColor:        Qt.rgba(0, 0, 0, 0)
  readonly property color capsuleBorderColor:  Qt.rgba(0, 0, 0, 0)
  readonly property real  capsuleBorderWidth:  0
  readonly property real  baseWidgetSize:      22

  // UI scale ratio. Noctalia plugins multiply lengths by this when
  // applyUiScale is true; we leave it at 1.
  readonly property real uiScaleRatio: 1.0

  // Helpers. Plugins pass screen names but in practice we ignore them and
  // return our shell-wide values.
  function getBarHeightForScreen(name)    { return 28 }
  function getCapsuleHeightForScreen(name) { return 22 }
  function getBarFontSizeForScreen(name)  { return fontSizeM }
  function getBarRadiusForScreen(name)    { return radiusM }

  function pixelAlignCenter(parentSize, childSize) {
    return Math.round((Number(parentSize) - Number(childSize)) / 2)
  }

  function toOdd(n) {
    var i = Math.floor(Number(n))
    return i | 1
  }
}
