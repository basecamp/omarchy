# Neovim

[Neovim](https://neovim.io/) is a modern implementation of [the vi editor](<https://en.wikipedia.org/wiki/Vi_(text_editor)>) created by Bill Joy all the way back in 1976. It's a modal editor where insert mode and command mode are separated, and it's a bit of a superpower once you learn even just a subset of the incredibly deep key command set. But it's also quite the learning curve!

If you're totally new to vim-style editing, I recommend you checkout [ThePrimeagen's Vim As Your Editor series](https://www.youtube.com/watch?v=X6AR2RMB5tE&list=PLm323Lc7iSW_wuxqmKx_xxNtJC_hJbQ7R) on YouTube. That'll teach you the basics. Just know that unlike more similar mainstream editors, it's going to take you longer to get basic proficiency with vim. But once you do, the payoff is also larger.

Now Neovim is basically infinitely configurable. If you really want to go nuts, you can create your own Neovim configuration from scratch. There's a great course from [Typecraft on setting up Neovim from scratch](https://www.youtube.com/watch?v=zHTeCSVAFNY). And [ThePrimeagen has one as well](https://www.youtube.com/watch?v=w7i4amO_zaE).

But Omarchy ships with a complete Neovim setup — the `omarchy-nvim` package — that's been lovingly tuned to showcase the best of what's possible out of the box. Without you having to write a single line of configuration! It's built on [LazyVim](https://www.lazyvim.org/), a distribution of Neovim plugins and configurations. It's awesome.

## LazyVim Basics

As mentioned, I'm not going to teach you vim in this short introduction, but I can show you a few basics of LazyVim, and how to get around.

First, Neovim has the idea of the leader key. That's basically the gateway to all the commands. LazyVim has set that to `Space`. So just press that, wait a second, and you'll see a bunch of options explained inline like this:

Here are some basic commands I use all the time:

- `Space Space` - Fuzzy-find any file in the current directory.
- `Space S G` - Search all files using grep with a preview.
- `Space E` - Toggle the file tree on/off.
- `Ctrl + W W` - Hop from the file tree to the editor and back.
- `Shift + H` - Move left between the open tabs (vim calls them buffers).
- `Shift + L` - Move right between the open tabs.
- `Space B D` - Close a tab.
- `Space B O` - Close all other tabs but the current.
- `Space G G` - Launch LazyGit in a floating pane from the current directory.
- `Space U W` - Toggle soft wrap.

While you're in the file tree (`Space E` to reveal, `Ctrl + W W` to hop over there), you can add a new file with `a` or a new directory with `A`. Press `?` while in the tree to see all commands.

If you want to pickup the basic vim language, I've written about [the three-part syntax](https://world.hey.com/dhh/wonderful-vi-a1d034d3) and how to pull off those sick combo moves!

You can see all the possible commands on [the LazyVim Keymaps page](https://www.lazyvim.org/keymaps).

## Starting Neovim

You can start Neovim using `Super + Shift + N` (the binding launches your default editor, which is Neovim out of the box), but it's usually easier to drive it from the terminal by navigating to the directory you wish to work in and typing `n`. The `n` is the alias for `nvim`, which will use the the present directory to open by default. You can open a single file with `n myfile.txt`.

## Using Neovim for sudo edits

If you need to edit files that you can only change as a super user, you can use neovim with all your plugins setup by running `sudoedit /etc/sudoers.d/00-sudo-only-file`.
