# The Omarchy menu

The menu is the `omarchy.menu` plugin of the Quickshell desktop, with its
content defined as data in `default/omarchy/omarchy-menu.jsonc` (read at
runtime from `$OMARCHY_PATH`) and overlaid by the user's
`~/.config/omarchy/extensions/omarchy-menu.jsonc`. The shell parses both files
at startup and watches them for changes, so the keybind → IPC → visible path
never shells out to parse anything, and edits to either file take effect
without restarting the shell. Rendering and behavior live in
`shell/plugins/menu/Menu.qml`; the pure logic lives in
`shell/plugins/menu/MenuModel.js`, which is plain JavaScript that Node can
also load — the shell tests in `test/shell.d/menu-test.sh` and
`menu-guards-test.sh` exercise it directly.

JSONC here means JSON plus comments and trailing commas, stripped by the
parser rather than a real JSONC grammar: only whole-line `//` comments are
removed, so an inline trailing comment breaks the parse. A file that fails to
parse contributes no entries — a broken user extension silently drops every
user entry while the shipped menu keeps working.

## File shape

Almost every top-level key is an entry id, and `keybindings` is the exception: it configures the menu rather than declaring a row, and `parseMenuJsonc` skips it for that reason. Entries may also be nested under an explicit `items` key, in which case the carve-out does not apply and a row may be called `keybindings` like anything else. Nothing shipped uses the wrapper.

## Entry schema

Entries are object keys. The dotted id is the tree: `trigger.share.file` is a
child of `trigger.share`, and an id with no dot sits on the root menu. There
is no separate parent field to keep in sync — where an entry appears follows
from what it is called (an explicit `parent` is accepted but nothing shipped
uses one).

Kind is inferred rather than declared: an entry with `action` is an action,
one with `target` is a link to another submenu, and anything else is a
submenu. The fields:

| Field | Meaning |
|---|---|
| `icon` | Glyph in the icon column (usually Nerd Font) |
| `iconFont` | Font family for the glyph when it differs from the menu font — how the private `omarchy` font's brand glyphs render |
| `label` | Visible row title; defaults to the id |
| `title` | Header text when the submenu is open; defaults to `label`. Lets a row read "Browser" under Defaults while the open menu says "Default Browser" |
| `action` | Shell command to run, detached, when selected |
| `target` | Existing submenu id to open; makes the row a link |
| `provider` | Runtime row source for this submenu (see Providers) |
| `aliases` | Alternate `omarchy menu summon <name>` routes; also searchable |
| `description` | Subtitle shown while searching, and extra search text matched by whole word |
| `when` / `checked` / `disabled` | Shell conditions (see Guards) |

Do not add `aliases` to new entries. They are reserved for established
alternate names users already type (`power-menu`, `settings`), kept for
compatibility — see `AGENTS.md`. Search does not need them: labels, the last
id segment, and descriptions are all searchable.

## Load and merge

`mergeMenuSources` overlays user entries on the defaults per key: reusing a
shipped id replaces only the fields you declare, so an extension can retitle
or re-icon a row without re-declaring its action, and an overridden entry
keeps its original position in the list. New ids append. A `root` entry is
injected if neither file declares one.

The sample extension at `config/omarchy/extensions/omarchy-menu.jsonc`
(refreshed into `~/.config/`) documents the format in its header and ships
only comments, so the default state adds nothing.

## Keybindings

The keys that drive the menu are data in the same two files as the rows, under the top-level `keybindings` key, mapping an action to the list of keys that trigger it:

```jsonc
"keybindings": {
  "next":     ["DOWN", "CTRL + J"],
  "back":     ["LEFT", "CTRL + H"],
}
```

The actions are `next`, `prev`, `pageNext`, `pagePrev` (six rows at a time), `activate` and `back`. A binding is one string in the Hyprland DSL `config/hypr/bindings.lua` already writes: modifiers and key joined by `+`, surrounding whitespace tolerated, parsed case-insensitively, so `CTRL + J`, `Ctrl+J` and `ctrl + j` are the same binding. The modifiers are `SUPER`, `CTRL`, `ALT` and `SHIFT`; the key is one of the names `KEY_NAME_MAP` carries — the arrows, the page and editing keys, `F1`–`F12`, `PRINT`, and the punctuation Omarchy's own Hyprland bindings name (`COMMA`, `SLASH`, `PERIOD`, `GRAVE`) — or any single character, which resolves to itself. Qt names outside that table, such as `QUOTELEFT` or `CAPSLOCK`, are not accepted; write the character instead. Shipped defaults and documentation emit the canonical uppercase.

Modifiers match exactly in two of the three cases. A binding that names modifiers requires them exactly, so `CTRL + SHIFT + J` never fires a `CTRL + J` binding; a binding on a plain character does too, so `CTRL + J` never fires a `J` binding and the letter stays typeable. The exception is an unmodified binding on a named key — `DOWN`, `RETURN` — which fires whatever is held. That is deliberate: the hardcoded dispatch this replaced tested `event.key === Qt.Key_Down` with no modifier check, so `SHIFT + DOWN` moved the selection and `CTRL + RETURN` activated, and the shipped defaults have to keep behaving that way.

`parseBinding` resolves the whole string or none of it. An unknown modifier drops the binding with a warning rather than falling back to the bare key, which is what keeps `CTL + J` from quietly binding plain `J` and taking the letter away from search — the dispatch consults bindings before it treats a keystroke as typing. Key names refuse the same way. Because `normalizeKeybindings` leaves out an action whose bindings all failed, a whole block of typos keeps the shipped keys instead of unbinding the action.

Binding an unmodified character key costs you that character in search: bound to `back` you lose it only as the first character, since the hold-back rule below returns it once there is text; bound to any other action you lose it entirely, because the dispatch consults bindings before it treats a keystroke as typing. Modified bindings cost nothing.

One rule involves the filter, and it belongs to `back` alone: an unmodified `back` binding does not fire while the search box has text. That is why `LEFT` navigates out of a submenu but moves through a search being typed, and why the same action can carry `CTRL + H`, which stays live mid-search because nobody types it into a search box. Every other action keeps working while filtering — navigating and activating a filtered list is the point of filtering it.

The rule replaced a per-binding `whenFilterEmpty` flag. On `LEFT` the flag did this job; on the shipped `BACKSPACE` binding it was already unreachable, since `Util.editsFilter` answers ahead of the binding table and claims Backspace whenever the filter has text.

`mergeKeybindings` combines the user's block with the defaults per action, but additively rather than the way `mergeMenuSources` replaces per entry: the keys a user lists for an action are appended to the shipped ones, so binding `CTRL + N` to `next` adds it alongside `DOWN` instead of costing you the arrow key. An action left out keeps what the defaults bound. Unbinding is the explicit case — an action written as `[]` drops its keys entirely — and it is why `normalizeKeybindings` leaves out an action whose keys all failed to resolve rather than emitting it empty: a typo should cost you the key you misspelled, not the shipped ones it was joining. Shipped keys come first in the merged list, which only decides which binding `bindingMatches` reports when two of them would both fire. Resolution happens once per load, not per keystroke.

Three things are handled ahead of every binding and cannot be rebound: `Escape` (clear the filter, then close), `Delete` (uninstall the selected app), and the filter-editing keys `Backspace` and `Ctrl+U` that `Util.editsFilter` owns. Because `editsFilter` answers first but only when the filter has text, a binding on `Backspace` still works on an empty filter — which is how the shipped `back` reaches it. Bindings are then tried in the fixed order above and the first match wins, so binding one key to two actions resolves by that order.

`DEFAULT_KEYBINDINGS` in `MenuModel.js` is not the source of truth; the shipped bindings are the block in `default/omarchy/omarchy-menu.jsonc`. It exists so a default file that is missing or unparseable cannot leave the menu without a keyboard, the same job `builtinShellConfig` does for `shell.json` in `shell.qml`. It is written in the same string form a user writes and resolved through the same `parseBinding`, so a spelling that works there works here.

## Guards

`when`, `checked`, and `disabled` are bash conditions. The shell never
evaluates them on the open path: all guards in the menu are batched into a
single bash process per (re)load and per open, reporting `<id>:<w|c|d>:<0|1>`
lines. The menu opens immediately on the previous evaluation's answers, so
the batch's runtime is exactly how long a row can contradict the state it
describes — which is why the batch works hard to be fast:

- Package and command presence (`omarchy-pkg-present` and friends) are
  answered in-process from one `pacman -Q` snapshot instead of a fork per
  row. The snapshot resolves provides too, so gvim answers for vim.
- Commands that several rows read a value from — every Defaults > Browser row
  compares against `$(omarchy-default-browser)` — run once, with the captured
  answer substituted into each expression. The reader list is
  `GUARD_READERS` in `MenuModel.js`; a new `$(omarchy-...)` reader used by
  more than one row must be added there, and `menu-guards-test.sh` fails the
  build if it is not.

The three guards differ in what failure means:

- `when` hides the row when it fails. A submenu whose visible descendants
  are all hidden disappears with them (provider-backed submenus stay, since
  their rows load on demand).
- `checked` appends ✓ when it succeeds — the "this is the current choice"
  marker on defaults, DNS, channel rows.
- `disabled` keeps the row listed but dims it, marks it ✓, and makes it
  unselectable: cursor, pointer, and Enter all step over it, and search omits
  it. The Install submenus use it so software already on the machine reads as
  installed rather than vanishing from the list it was installed from — the
  list stays a catalog of what Omarchy can install. Since a dimmed row means
  "you already have this", it earns the same ✓ as `checked` does elsewhere.

Install rows should therefore carry `disabled:` with the presence check, not
`when:`; Remove rows are the opposite, hiding via `when:` what is not there
to remove. `menu-test.sh` enforces the Install side of this convention.

## Providers

A submenu with `provider: "name"` gets its rows at runtime instead of from
JSONC. The names are defined by the shell, not the menu file — an extension
can point a submenu at an existing provider but cannot declare a new one:

- `apps` is QML-native: rows come from the shared AppLibrary (desktop
  entries), carrying image icons, launch feedback, and uninstall support like
  the launcher. App rows are searchable by their desktop Keywords but never
  routable, so an installed app cannot capture a menu route (htop ships
  `Keywords=system;...`, and SUPER+ESCAPE must still open the system menu).
- `fonts` and `power-profiles` are bash one-liners in the `providers` map in
  `Menu.qml`. The contract is one tab-delimited line per row:
  `label\tvalue\tcurrent`. The row whose value equals `current` gets the ✓
  icon, and selection runs the spec's `actionFor(value)`. Row ids are
  `<menuId>.<slugify(value)>`, with a `-` appended on collision so two values
  that slugify alike cannot silently drop a row.

A provider marked `volatile` re-runs every time its submenu is entered — a
font installed since the shell started shows up without a restart — but not
on search keystrokes, which would restart the same enumeration per key.

`swapProviderRows` in `MenuModel.js` merges the results: rows carry the id of
the submenu that produced them, so a provider that runs again drops its
previous batch without disturbing static children declared in JSONC. Both it
and the app merge return fresh item maps for the caller to assign in one go —
writing into a map held by a QML `var` property occasionally loses the write,
which used to duplicate launcher rows. Never mutate `root.items` in place.

Adding a provider means adding an entry to the `providers` map in `Menu.qml`
(script, icon, `actionFor`, optionally `volatile`) and pointing a submenu at
it with `provider:`.

## Driving the menu from the CLI

`bin/omarchy-menu` is a thin wrapper over the standard plugin IPC surface:

```bash
omarchy menu                    # toggle the root menu
omarchy menu toggle system      # open at a route, or close if already open
omarchy menu summon style.theme # always open (no close-if-visible)
omarchy menu close
omarchy menu refresh            # re-parse the JSONC files
omarchy menu ping
```

A route is an item id or a declared alias, case-insensitive, with
underscores normalized to dashes. An exact id beats any alias; empty input,
`go`, and `menu` mean root; an unknown string falls through as a literal id
so a misspelling still attempts to open that id. Summoning a route that
resolves to an action — an alias for a leaf, like `screenrecord-stop` — runs
the action directly instead of opening an action with no children, and a
link is followed to its target. The default Hyprland bindings in
`default/hypr/bindings/utilities.lua` all go through this surface
(SUPER+SPACE toggles root, SUPER+ESCAPE the system menu, and so on).

## Select and input modes

The same plugin doubles as the system's dmenu. `omarchy-menu-select` and
`omarchy-menu-input` summon it with a `mode: select` or `mode: input`
payload, then block on a tempfile handshake: the shell writes the selection
to `selectionFile` and touches `doneFile`, and cancellation (empty
selection) exits 1. A select option is `label`, `glyph\tlabel`, or
`glyph\tlabel\tsubtext` — the glyph shows but never returns, the subtext
renders under the label, filters with it, and comes back as
`label\tsubtext` so callers with same-named rows get a stable key. This is
how the pickers behind menu actions (`omarchy-menu-plugin`,
`omarchy-menu-timezone`, ...) present lists without owning any UI.
