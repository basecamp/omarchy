# Text Extraction & Dictation

### Text Extraction

Hit `Super + Ctrl + PrtScr` to select a region on the screen for text extraction. The tesseract open source OCR model will then quickly convert that selection into text and place it on the clipboard. Then you just hit `Super + V` to paste.

This is very helpful for grabbing addresses out of image footers or phone numbers embedded in website headlines.

 ![text-extraction](images/text-extraction.webp)

### Dictation

Omarchy offers AI dictation via [Voxtype](https://voxtype.io/). You install it via _Install > AI > Dictation_ through the Omarchy menu. By default, it'll load a base English model that takes up 150MB. But you can tweak which model you'd like to use by running `voxtype setup model` in the terminal. And you can tweak all the settings via `~/.config/voxtype/config.toml`.

Once installed, you dictate by holding down `F9` or by toggling with `Super + Ctrl + X`, and the dictated text will appear in the focused input area.
