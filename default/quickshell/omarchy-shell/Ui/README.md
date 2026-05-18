# qs.Ui — Omarchy shell UI kit

Reusable QML components for omarchy-shell's built-in panels and any
third-party plugin that wants a consistent look and behaviour. Every
type is exposed under the `qs.Ui` module via the `qmldir` next to this
file, so consumers write:

```qml
import qs.Ui

Item {
  PanelSeparator { foreground: someColor }
  PillButton { text: "Click me"; onClicked: ... }
}
```

Theme tokens (corner radius, accent, focus styling) live on the
`qs.Commons.Style` singleton; every Ui component already binds to them,
so toggling `omarchy style corners <sharp|round>` updates every
consumer in one shot.

## Visual reference

Run the dev gallery to see every component live:

```bash
omarchy-shell-ipc shell summon omarchy.dev-gallery '{}'
```

The gallery renders the real components (not copies), so it doubles as
a smoke test — if a component starts misbehaving the gallery is the
fastest place to see it.

## Components

Grouped by what they're for, not alphabetically.

### Panel surfaces

| Type | Purpose |
|---|---|
| `KeyboardPanel` | Layer-shell popup with `WlrKeyboardFocus.Exclusive`. Use for panels summoned from a bar widget that need keyboard focus on map (j/k navigation, inline editors). |
| `PopupCard` | xdg-popup based panel. Use for click/hover overlays that don't need to steal keyboard focus (calendar, weather flyout). |

### Cursor model

| Type | Purpose |
|---|---|
| `CursorSurface` | Rectangle that paints fill + 1px border when `hasCursor` is true, and fill alone when `current` is true. The foundation for "single highlight on screen across keyboard and mouse" rows. Never read `containsMouse` for visuals — bind `hasCursor` from the panel's cursor state instead. |
| `PanelKeyCatcher` | Item that emits semantic signals: `moveRequested(dx, dy)`, `activateRequested()`, `closeRequested()`, `deleteRequested()`, `textKey(string)`. Drop inside a panel root, wire signals to the panel's state mutators. `blocked: true` freezes everything except — nothing; it's a hard gate for inline editors. |

### Interactive primitives

| Type | Purpose |
|---|---|
| `PillButton` | Rounded button with optional icon + label + tooltip. Has `active`, `hasCursor` (keyboard cursor), `focusable` (Tab-focus with accent ring), `bordered` (persistent 1px idle border for primary form buttons), and `enabled`. Hover and keyboard cursor render identically (fill + border) via the shared `hot` state; Tab-focus uses an accent ring that wins over both. |
| `CursorPill` | `PillButton` that participates in a panel's single-cursor model. Adds a `hovered(bool)` signal so the panel can update its cursor state on mouse enter/leave. Use for DNS-pill / header-pill / segmented-choice patterns. |
| `ChoiceButton` | A single button in a mutually-exclusive choice group (segmented control). `selected` uses accent fill+border; focus uses `Style.focusBorderColor` so keyboard nav reads differently from selection. |
| `Toggle` | Title + description + switch. Click anywhere on the row to flip; caller updates `checked` in response. `rounded` auto-detects from `Style.cornerRadius` so the switch is a pill on round-corners themes and square on sharp; override per-instance to force one or the other. |
| `TextField` | Single-line input. Inherits from Qt Quick Controls `TextField` so all of its base API (text, placeholderText, accepted, validator, ...) is available. Adds `password: bool`, `foreground` / `accent` / `selectionTint` color overrides, and `horizontalPadding` / `verticalPadding` size knobs. Focus styling uses `Style.focusBorderColor` to match `Toggle` and `ChoiceButton`. `hasCursor` paints the same focus ring so a panel cursor lands on the field identically. For hover wiring use QQC TextField's inherited `hovered` property (via `onHoveredChanged`) — the sibling signal name would shadow it. |
| `Dropdown` | Single-select dropdown with a themed popup (no platform-native ComboBox chrome). `options` accepts `string[]` or `[{ value, label }]`. Keyboard: Tab to focus trigger, Enter/Space opens, j/k or arrows walk options, Enter selects. `hasCursor` paints the focus ring on the trigger; emits `hovered(bool)`. `popupOpen` plus `open()` / `close()` / `toggle()` let a parent panel suspend its own key catcher while the popup owns keys. |
| `SearchableDropdown` | `Dropdown` with an embedded search field at the top of the popup that filters options as you type. Use when the option count is high enough that scanning is friction (e.g. bar settings "+ Add widget"). Options can also carry a `description` string that the filter matches against. Same `hasCursor` / `popupOpen` / `open()` / `close()` / `toggle()` / `hovered(bool)` surface as `Dropdown`. |
| `PanelActionButton` | 22×22 right-edge action button (confirm, forget, unpair). `hoverColor` swaps between default foreground tint and urgent (red) tint. `focusable: true` enables Tab-focus with an accent ring — used for the bar settings widget-card row controls. `hasCursor: true` paints the hover fill so a panel cursor can land on the button directly when it isn't living inside a `CursorSurface` row; emits `hovered(bool)`. |
| `PanelSlider` | Volume/progress slider. Drag, click track, or wheel. `moved(value)` fires per change, `released(value)` once at end. (Named to avoid colliding with `QtQuick.Controls.Slider`.) |
| `WidgetButton` | Bar widget chrome — for the strip itself, not for inside panels. |

### Structure

| Type | Purpose |
|---|---|
| `PanelSeparator` | 1px alpha rule between sections. `strength` tweaks opacity. |
| `PanelSectionHeader` | Small-bold label that introduces a section ("DNS provider", "Wi-Fi networks"). |
| `PanelToolTip` | Styled wrapper around Qt's `ToolTip`. Drop inside the hovered item and bind `visible` to the hover state. Use property names `panelForeground`/`panelBackground` (not `foreground`/`background`) to avoid clashing with `ToolTip`'s built-ins. |

## Theme integration

`qs.Commons.Style` exposes:

- `cornerRadius` — mirrors `~/.local/state/omarchy/toggles/quickshell-menu.json`, hot-reloaded
- `focusBorderColor`, `focusFillColor`, `focusBorderWidth` — derived from `Color.accent`
- `hotFill` — the standard hover/cursor tint (foreground at 0.12 alpha)

`qs.Commons.Color` exposes the foundational palette plus per-surface
roles loaded from the theme's `colors.toml` + `shell.toml`. Components
in this kit default-bind to `Color.foreground` / `Color.accent` /
`Color.background` so a caller with no explicit theme just works.

## Conventions

- Every interactive primitive exposes `hasCursor: bool` and emits
  `hovered(bool)` so a parent panel can wire it into the same
  cursor-model recipe used by the wifi / audio / bluetooth / monitor
  panels: the panel root owns `focusSection` + `selectedIndex`, each
  element binds `hasCursor: root.focusSection === "X" && root.selectedIndex === N`,
  and `onHovered` updates the same root state on pointer enter/leave.
  Popups (`Dropdown`, `SearchableDropdown`) also expose `popupOpen` so
  the panel's `PanelKeyCatcher` can be `blocked` while the popup owns
  keyboard input.
- Components are stateless about the values they display. They emit
  signals and let the caller mutate. Don't bake panel-specific state
  machines into kit components.
- Mouse hover and keyboard cursor should converge on a single visual
  state. Bind `hasCursor` from the panel root; have hover handlers
  update the same root state via `onHovered`.
- Property names follow the underlying QML type's convention. Where a
  clash is unavoidable (`Toggle`/`ToolTip` already define `background`
  in QQC), the kit uses a `panel*` prefix.

## Adding a new component

1. Write the QML file in this directory.
2. Add a line to `qmldir`: `TypeName 1.0 TypeName.qml`.
3. Add a live demo section to `plugins/dev-gallery/GalleryPanel.qml`
   using the real component — copy/paste reimplementations defeat the
   smoke-test value of the gallery.
4. Update the table above.
