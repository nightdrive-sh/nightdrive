#!/bin/bash
# Prints the ids (foo.desktop) of desktop entries whose program isn't there: TryExec, or else Exec's first word, not
# found as an absolute path or on PATH. The Launcher leaves them out of Apps: an entry outlives its package when it is
# a local copy or a link (an overlay's ~/.local/share/applications/*.desktop), and DesktopEntries doesn't check TryExec.
# An entry in an earlier directory hides the same id further on, as in DesktopEntries (XDG order).
dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
# Hyprland's PATH may lack ~/.local/bin, but an entry may still name a program there
PATH="$PATH:$HOME/.local/bin"
seen=" "
IFS=: read -ra dirlist <<< "$dirs"
for d in "${dirlist[@]}"; do
  [ -d "$d/applications" ] || continue
  while IFS= read -r f; do
    id=$(printf %s "${f#"$d/applications/"}" | tr / -)
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    prog=$(awk -F= '
      /^\[/ { if (seen) exit; seen = 1; next }
      $1 == "TryExec" && !t { t = substr($0, 9) }
      $1 == "Exec" && !e { e = substr($0, 6) }
      END { if (t != "") print t; else { split(e, w, " "); print w[1] } }
    ' "$f" | tr -d '"')
    # env VAR=… prog and the like: not worth parsing, so such an entry stays
    case "$prog" in ""|env) continue ;; esac
    command -v "$prog" >/dev/null 2>&1 || echo "$id"
  done < <(find "$d/applications" -name '*.desktop' 2>/dev/null)
done
