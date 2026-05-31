# GhostNotch opt-in zsh shell integration.
# Source this file manually from .zshrc to enable working-directory reporting.

_ghostnotch_report_cwd() {
  printf '\033]7;file://%s%s\033\\' "${HOST:-localhost}" "$PWD"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _ghostnotch_report_cwd
