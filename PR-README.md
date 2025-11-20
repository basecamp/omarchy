This PR proposes built-in dictation.

Inspired by [thePrimeagen's stream]() and their Cursor pedal, I wanted to see if there was an easy way to get voice dictation into an Omarchy keybind. I found nerd-dictation, installed, ydotool, and after a bit of debugging it just worked.

Typing a long set of instructions into OpenCode or Cursor can get annoying, and I find myself often giving sub-par instructions just because I don't want to type a novel into each prompt... but now I can just speak it.

Proposing this PR in case @dhh and others in the Omarchy community want to integrate this functionality into the out of the box Omarchy experience. I have not yet tested this on a fresh install, but I believe that all of the necessary configuration has been added. If anybody has a machine they don't mind hard-refreshing with a fresh Arch install, a test would be greatly appreciated. 

It leverages [nerd-dictation](https://github.com/ideasman42/nerd-dictation) to perform voice to text transcrtiption with a small local model downloaded on OS install at `~/.config`, uses built-in `parec` for audio recording, and an added dependency `ydotool` to simulate input on the cursor with Wayland. This is added to the hypr autostart to launch the input emulation daemon in the background, but this could be optimized in the future.


