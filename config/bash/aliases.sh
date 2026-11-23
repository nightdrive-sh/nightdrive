# eza replaces ls (install: sudo dnf install eza). The aliases are only active if eza is found.
# Icons come from the Symbols Nerd Font fallback (bundled with kitty); colours follow the terminal palette.
if command -v eza >/dev/null 2>&1; then
  export EZA_ICON_SPACING=2       # gap between icon and name (wide Nerd Font icons cover a single space)
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -l --icons --group-directories-first --git'          # long list + git status
  alias la='eza -la --icons --group-directories-first --git'         # hidden files too
  alias lt='eza --tree --level=2 --icons --group-directories-first'  # tree view (2 levels); e.g. lt -L3 or lt -a
fi

# open, as on a Mac: opens files, folders and links in their default app, several at once, e.g. open .
# gio open, as Files does, not xdg-open: under Hyprland xdg-open knows no desktop and asks file(1) for the type, which
# calls a .md (or .csv, .json) plain text and opens it in text/plain's app instead of its own.
open() {
  (( $# )) || set -- .
  local f opener=xdg-open
  command -v gio >/dev/null 2>&1 && opener="gio open"
  for f in "$@"; do $opener "$f" >/dev/null 2>&1 & disown; done
}
