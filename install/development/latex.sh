#!/bin/zsh

# install everything, it's about 600 MB, might be skimmable to 350 but w/e
sudo pacman -S --noconfirm --needed \
  python-pylatexenc texlive-basic texlive-latex texlive-latexextra \
  texlive-latexrecommended texlive-fontsextra \
  texlive-fontsrecommended texlive-mathscience texlive-xetex

