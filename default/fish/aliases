# Alias

alias cd='z'
alias l='eza -lh --color=always --icons=always' # long list
alias ls='eza -1 --icons=always --color=always' # short list
alias ll='eza -lha --color=always --icons=always --sort=name --group-directories-first' # long list all
alias ld='eza -lhD --color=always --icons=always' # long list dirs
alias lt='eza --icons=always --tree' # list folder as tree
alias vc='code'

alias shutdown='systemctl poweroff'
alias c='clear'

alias cd="zd"
zd() {
  if [ $# -eq 0 ]; then
    builtin cd ~ && return
  elif [ -d "$1" ]; then
    builtin cd "$1"
  else
    z "$@" && printf "\U000F17A9 " && pwd || echo "Error: Directory not found"
  fi
}
open() {
  xdg-open "$@" >/dev/null 2>&1 &
}

alias v='$EDITOR'
alias vim='$EDITOR'
alias vi='$EDITOR'

# alias cleanup='~/.config/ml4w/scripts/cleanup.sh'

#fzf
alias find='nvim $(fzf --preview="bat --color=always {}")'

alias cat='bat --style header --style snip --style changes --style header' # cat
alias cat='bat'

alias pn=pnpm

# Handy change dir shortcuts
abbr .. 'cd ..'
abbr ... 'cd ../..'
abbr .3 'cd ../../..'
abbr .4 'cd ../../../..'
abbr .5 'cd ../../../../..'

# Always mkdir a path (this doesn't inhibit functionality to make a single dir)
abbr mkdir 'mkdir -p'
