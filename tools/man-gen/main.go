// omarchy-man generates an omarchy(1) man page from `omarchy commands --all --json`.
//
// Usage:
//   omarchy commands --all --json | go run . > man/man1/omarchy.1
//   go run . -in commands.json -out man/man1/omarchy.1
//
// Regenerate whenever omarchy adds/changes commands — don't hand-edit the output.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
	"time"
)

type Command struct {
	Route        string   `json:"route"`
	Binary       string   `json:"binary"`
	Group        string   `json:"group"`
	Name         string   `json:"name"`
	Summary      string   `json:"summary"`
	RequiresSudo bool     `json:"requires_sudo"`
	Hidden       bool     `json:"hidden"`
	Args         string   `json:"args"`
	Examples     []string `json:"examples"`
	Aliases      []string `json:"aliases"`
}

type commandsFile struct {
	OK       bool      `json:"ok"`
	Commands []Command `json:"commands"`
}

// groupDescriptions mirrors GROUP_DESCRIPTIONS in bin/omarchy (which is what
// `omarchy --help` prints as its "Groups:" section). The JSON from
// `omarchy commands` carries no group-level metadata, so this is maintained
// by hand and needs to be re-synced whenever bin/omarchy's GROUP_DESCRIPTIONS
// changes. Unknown future groups fall back to a title-cased "<group> commands".
var groupDescriptions = map[string]string{
	"agent":         "AI coding agent usage data",
	"audio":         "Audio input and output controls",
	"bar":           "Omarchy shell bar layout and settings",
	"battery":       "Battery status helpers",
	"bluetooth":     "Bluetooth device controls",
	"branch":        "Omarchy git branch management",
	"branding":      "About and screensaver branding",
	"brightness":    "Display and keyboard brightness",
	"capture":       "Screenshots and screen recording",
	"channel":       "Omarchy release channel management",
	"clipboard":     "Clipboard helpers",
	"cmd":           "Command and shortcut helpers",
	"config":        "System configuration helpers",
	"debug":         "Diagnostics and support logs",
	"default":       "Default application selection",
	"dev":           "Omarchy development tools",
	"disk":          "Disk performance helpers",
	"display":       "Display and text scaling",
	"dns":           "DNS resolver configuration",
	"drive":         "Drive selection and encryption",
	"file":          "File selection helpers",
	"finalize":      "Finalize user setup",
	"font":          "Font management",
	"games":         "Game launchers and helpers",
	"hibernation":   "Hibernation setup and removal",
	"hook":          "User hook runner",
	"hw":            "Hardware detection and controls",
	"hyprland":      "Hyprland window, monitor, and toggle controls",
	"install":       "Optional software installers",
	"installed":     "Installed optional service checks",
	"launch":        "Application launchers",
	"menu":          "Omarchy menu commands",
	"migrate":       "Migration runner",
	"mise":          "Mise tool wrappers",
	"monitor":       "Monitor status helpers",
	"network":       "Network status helpers",
	"notification":  "Notification helpers",
	"osd":           "On-screen display status helpers",
	"pkg":           "Package management helpers",
	"plugin":        "Omarchy shell plugin and bar widget management",
	"plymouth":      "Plymouth boot theme management",
	"power":         "Power supply detection",
	"powerprofiles": "Power profile management",
	"refresh":       "Reset config to defaults",
	"reinstall":     "Reinstall and reset workflows",
	"reminder":      "Desktop notification reminders",
	"remove":        "Removal workflows",
	"restart":       "Restart Omarchy components",
	"screensaver":   "Screensaver branding and animation",
	"setup":         "Interactive setup wizards",
	"shell":         "Omarchy shell IPC helpers",
	"snapshot":      "System snapshots",
	"sudo":          "Sudo configuration helpers",
	"system":        "System status, reboot, shutdown, logout, and lock",
	"tailscale":     "Tailscale helpers",
	"theme":         "Theme management",
	"toggle":        "Toggle Omarchy features",
	"transcode":     "Image and video transcoding",
	"tui":           "Terminal UI launchers",
	"update":        "Omarchy and system updates",
	"version":       "Version and channel information",
	"voxtype":       "Voxtype dictation",
	"weather":       "Weather status",
	"webapp":        "Web app launchers",
	"wifi":          "Wi-Fi helpers",
	"windows":       "Windows VM management",
}

func groupDesc(g string) string {
	if d, ok := groupDescriptions[g]; ok {
		return d
	}
	return strings.ToUpper(g[:1]) + g[1:] + " commands"
}

// stripPUA replaces runs of Unicode Private Use Area codepoints with a
// placeholder. Omarchy examples sometimes embed Nerd Font icon glyphs (e.g.
// U+F051B) that only render in a patched terminal font; groff has no glyph
// for them and warns/garbles the output, and a plain man page reader
// wouldn't see the icon anyway. Dropping the rune outright (rather than
// placeholding it) can leave a preceding flag with no value at all, e.g.
// `-g <icon-was-here>` collapsing to a dangling `-g`.
func stripPUA(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	inPUA := false
	for _, r := range s {
		if isPUA(r) {
			if !inPUA {
				b.WriteString("<icon>")
				inPUA = true
			}
			continue
		}
		inPUA = false
		b.WriteRune(r)
	}
	return b.String()
}

func isPUA(r rune) bool {
	return (r >= 0xE000 && r <= 0xF8FF) || // BMP PUA
		(r >= 0xF0000 && r <= 0xFFFFD) || // Supplementary PUA-A
		(r >= 0x100000 && r <= 0x10FFFD) // Supplementary PUA-B
}

// typographicEscapes maps Unicode punctuation that shows up in command
// summaries/examples to groff's native glyph escapes. Without this, groff
// reads the raw UTF-8 bytes as individual invalid-input-character codes
// unless invoked with -k/-Tutf8 (which `groff -man -ww -z` isn't), so
// `omarchy display text size`'s em dash summary would fail that check.
var typographicEscapes = strings.NewReplacer(
	"—", `\(em`, // —
	"–", `\(en`, // –
	"‘", `\(oq`, // '
	"’", `\(cq`, // '
	"“", `\(lq`, // "
	"”", `\(rq`, // "
	"…", `...`, // …
)

// escText escapes prose for groff: backslash, a leading '.' or '\''
// which troff would otherwise read as a request/macro, and Unicode
// punctuation groff can't take as raw UTF-8 input.
func escText(s string) string {
	s = stripPUA(s)
	s = strings.ReplaceAll(s, `\`, `\e`)
	s = typographicEscapes.Replace(s)
	if strings.HasPrefix(s, ".") || strings.HasPrefix(s, "'") {
		s = `\&` + s
	}
	return s
}

// escCode escapes command names / flags / args: same as escText, plus ASCII
// hyphens become \- so they render as real hyphens (not discretionary
// hyphenation points, and not the U+2212 minus some viewers substitute).
//
// It also inserts \: (a zero-width discretionary break, no visible hyphen)
// after each '|'. Enum-style args like
// <ruby|node|bun|deno|go|laravel|symfony|php|python|...> are long tokens
// with no spaces, so without this groff can't wrap them and either
// overflows the margin or emits a "cannot adjust line" warning.
func escCode(s string) string {
	s = escText(s)
	s = strings.ReplaceAll(s, "-", `\-`)
	s = strings.ReplaceAll(s, "|", `|\:`)
	return s
}

func main() {
	inPath := flag.String("in", "", "path to commands.json (default: stdin)")
	outPath := flag.String("out", "", "output path for the man page (default: stdout)")
	includeHidden := flag.Bool("all", false, "include commands marked hidden")
	version := flag.String("version", "", "omarchy version string for the page footer")
	flag.Parse()

	var r io.Reader = os.Stdin
	if *inPath != "" {
		f, err := os.Open(*inPath)
		if err != nil {
			fmt.Fprintln(os.Stderr, "omarchy-man:", err)
			os.Exit(1)
		}
		defer f.Close()
		r = f
	}

	var data commandsFile
	if err := json.NewDecoder(r).Decode(&data); err != nil {
		fmt.Fprintln(os.Stderr, "omarchy-man: parsing input:", err)
		os.Exit(1)
	}

	grouped := map[string][]Command{}
	for _, c := range data.Commands {
		if c.Hidden && !*includeHidden {
			continue
		}
		grouped[c.Group] = append(grouped[c.Group], c)
	}
	groups := make([]string, 0, len(grouped))
	for g := range grouped {
		groups = append(groups, g)
		sort.Slice(grouped[g], func(i, j int) bool {
			return grouped[g][i].Name < grouped[g][j].Name
		})
	}
	sort.Strings(groups)

	var w io.Writer = os.Stdout
	if *outPath != "" {
		f, err := os.Create(*outPath)
		if err != nil {
			fmt.Fprintln(os.Stderr, "omarchy-man:", err)
			os.Exit(1)
		}
		defer f.Close()
		w = f
	}
	bw := bufio.NewWriter(w)
	defer bw.Flush()

	writeManPage(bw, groups, grouped, *version)
}

func writeManPage(w *bufio.Writer, groups []string, grouped map[string][]Command, version string) {
	date := time.Now().Format("2 January 2006")
	verFooter := version
	if verFooter == "" {
		verFooter = "Omarchy"
	}

	fmt.Fprintf(w, `.TH OMARCHY 1 "%s" "%s" "Omarchy Manual"
.SH NAME
omarchy \- Omarchy command center
.SH SYNOPSIS
.B omarchy
.I command
[args...]
.br
.B omarchy commands
[\-\-all] [\-\-json] [\-\-check]
.br
.B omarchy
.I group
\-\-help
.br
.B omarchy
.I group command
\-\-help
.SH DESCRIPTION
.B omarchy
is the command center for an Omarchy system: a single entry point
routing to the group/command binaries that manage themes, hardware,
Hyprland, packages, and general system state.
.PP
Commands are organized into groups. Run
.B omarchy commands
for a live list, or
.BI "omarchy " group " \-\-help"
for help on a specific group.
.SH COMMON COMMANDS
.TP
.B omarchy update
Update Omarchy and system packages.
.TP
.B omarchy theme list
List available themes.
.TP
.BI "omarchy theme set " name
Apply a theme.
.TP
.B omarchy font list
List available fonts.
.TP
.B omarchy screenshot
Take a screenshot.
.TP
.B omarchy debug
Print debugging information.
.SH COMMANDS
`, date, verFooter)

	for _, g := range groups {
		fmt.Fprintf(w, ".SS %s \\- %s\n", escText(g), escText(groupDesc(g)))
		for _, c := range grouped[g] {
			// c.Route already includes the leading "omarchy" (e.g. "omarchy theme set").
			line := ".B " + escCode(c.Route)
			if c.Args != "" {
				fmt.Fprintf(w, "%s\n", line)
				fmt.Fprintf(w, ".I %s\n", escCode(c.Args))
			} else {
				fmt.Fprintf(w, "%s\n", line)
			}
			fmt.Fprintln(w, ".RS 4")
			fmt.Fprintln(w, escText(c.Summary))
			var notes []string
			if c.RequiresSudo {
				notes = append(notes, "Requires sudo.")
			}
			if len(c.Aliases) > 0 {
				notes = append(notes, "Alias: "+strings.Join(escAliases(c.Aliases), ", "))
			}
			if len(notes) > 0 {
				fmt.Fprintln(w, ".br")
				// notes are already groff-safe (a plain literal, or
				// escAliases output) — escText-ing the joined string
				// would double-escape the aliases' \- back-slashes.
				fmt.Fprintln(w, strings.Join(notes, " "))
			}
			for _, ex := range c.Examples {
				fmt.Fprintln(w, ".br")
				fmt.Fprintf(w, "Example: %s\n", escCode(ex))
			}
			fmt.Fprintln(w, ".RE")
			fmt.Fprintln(w, ".PP")
		}
	}

	fmt.Fprint(w, `.SH DISCOVERY
.TP
.B omarchy commands
List all commands.
.TP
.B omarchy commands \-\-all
Include commands explicitly marked hidden.
.TP
.B omarchy commands \-\-json
Machine\-readable command list.
.TP
.B omarchy commands \-\-check
Validate command metadata and routes.
.SH SEE ALSO
.UR https://manual.omarchy.org
Omarchy Manual
.UE
`)
}

func escAliases(a []string) []string {
	out := make([]string, len(a))
	for i, s := range a {
		out[i] = escCode(s)
	}
	return out
}
