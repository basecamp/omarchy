# Shell Tools

In addition to the standard Linux tools, Omarchy also ships with a bunch of enhanced shell tools. Here are the key ones.

## fzf

[fzf](https://junegunn.github.io/fzf/) gives you fuzzy finding of files via the `ff` alias. Go to any directory, type `ff`, and you'll be able to fuzzy find your way to any file in that tree, while seeing a preview of the files you're narrowing down on the right-hand side.

You can use `Ctrl + R` to use fzf to fuzzy find through your command history.

This tool is also used by Neovim when you type `Space Space`.

The full manual can be found via `man fzf`.

## Zoxide

[Zoxide](https://github.com/ajeetdsouza/zoxide) is a replacement for cd. It remembers the directories you've been in, so you can more easily jump to them next time. Say you do `cd ~/.config/omarchy` once. Next time, you can just do `cd omarchy` (or even just `cd oma`), and Zoxide will take you directly there.

The full manual can be found via `man zoxide`.

## ripgrep

[ripgrep](https://github.com/BurntSushi/ripgrep) searches the contents of files by using `rg <pattern> <path>`, like `rg Controller app/` to find all mentions of `Controller` in the directory app.

This tool is also used by Neovim when you type `Space S G`.

The full manual can be found via `man rg`.

## eza

[eza](https://eza.rocks/) is a replacement for ls. It gives you directory listings with more information, color, and icons. By default, eza has been aliased as ls. You can also use `lt` to get a listing of two-deep levels of nesting. `lsa` gives you a listing including hidden files. And `lta` a nested listing with hidden files.

The full manual can be found via `man eza`.

## fd

[fd](https://github.com/sharkdp/fd) is an easier to use replacement for `find`. Use `fd person.rb` to find a file called `person.rb` within the current tree. `fd person.rb /` will search the entire file system. `fd person.rb / -H` searches the entire file system, including hidden directories.

The full manual can be found via `man fd`.

## bat

[bat](https://github.com/sharkdp/bat) is `cat` with syntax highlighting, line numbers, and paging. Run `bat somefile.rb` and you'll see why it's hard to go back. It's also quietly doing work for you elsewhere: it's what colors your man pages, and what renders the previews in `ff`.

The full manual can be found via `man bat`.

## tldr

[tldr](https://tldr.sh/) is the antidote to man pages that open with three screens of history before showing you a single example. `tldr tar` gives you the handful of invocations you actually wanted.

## yt-dlp

[yt-dlp](https://github.com/yt-dlp/yt-dlp) downloads video from YouTube and hundreds of other sites. `yt-dlp <url>` grabs the best quality available into the current directory.

The full manual can be found via `man yt-dlp`.

## try

[try](https://github.com/tobi/try) makes it easy to manage programming experiments with date-stamped directories. All experiments live in `~/Work/tries` and you can access them via `try`.
