# GhostNotch opt-in zsh shell integration.
# Source this file manually from .zshrc to enable working-directory reporting.

_ghostnotch_osc7_escape() {
  local value="${1:-}"
  value="${value//%/%25}"
  value="${value//$'\a'/%07}"
  value="${value//$'\033'/%1B}"
  value="${value//$'\n'/%0A}"
  value="${value//$'\r'/%0D}"
  printf '%s' "$value"
}

_ghostnotch_report_cwd() {
  printf '\033]7;file://%s%s\033\\' \
    "$(_ghostnotch_osc7_escape "${HOST:-localhost}")" \
    "$(_ghostnotch_osc7_escape "$PWD")"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _ghostnotch_report_cwd
