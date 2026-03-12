# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.
Read more at [omarchy.org](https://omarchy.org).

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).

### HP Victus / Omen RGB Keyboard Colors

HP gaming laptops with RGB keyboards (Victus 15-fa2xxx series and newer Omen models) now have built-in color control using the stock `hp-wmi` driver.

**Usage:**
```bash
kbdcolor navy      # or red, green, blue, cyan, yellow, orange, purple, pink, teal, lime, violet, etc.

Recommended one-key binds (add to ~/.config/hypr/bindings.conf):

bindd = SUPER ALT, N, Keyboard Navy,   exec, kbdcolor navy
bindd = SUPER ALT, R, Keyboard Red,    exec, kbdcolor red
bindd = SUPER ALT, C, Keyboard Cyan,   exec, kbdcolor cyan
bindd = SUPER ALT, Y, Keyboard Yellow, exec, kbdcolor yellow
# add the rest from the full list in the kbdcolor script
