# `ssh NAME` to a VM, for bin/garage-ctl (sourced after its helpers: die, dir, good_name, read_conf, conf): each VM's sshd
# is forwarded to a port of its own on the host's loopback (vm.conf's SSH_PORT, lib/qemu.sh's hostfwd), so two can run at
# once, and ~/.ssh/config.d/garage names them: a Host block each, with its port and its user (vm.conf's USER, the one
# an image's first boot made). HostKeyAlias keeps each VM's host key under its name, not under [127.0.0.1]:PORT, which
# a VM made later on the same port would share. ~/.ssh/config gets one Include line for it, once.

SSH_DIR=${GARAGE_SSH_DIR:-$HOME/.ssh}     # a test's own, so it leaves the user's ssh alone
SSH_CONF=$SSH_DIR/config.d/garage
FIRST_PORT=2222

good_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
good_port() { [[ $1 =~ ^[0-9]+$ ]] && (($1 >= 1024 && $1 <= 65535)); }

# The ports the VMs have, one a line (NAME's left out: its own doesn't count against it)
vm_ports() {
  local d n SSH_PORT MEM CPUS ISO SSH_USER
  for d in "$ROOT"/*/; do
    n=$(basename "$d")
    [[ -f $d/vm.conf && $n != "${1:-}" ]] && good_name "$n" || continue
    read_conf "$n"; [[ -n $SSH_PORT ]] && echo "$SSH_PORT"
  done
  return 0
}

# The first port from FIRST_PORT up that no VM has and nothing on the host listens on now
free_port() {
  local p=$FIRST_PORT used; used=$(vm_ports "${1:-}")
  while grep -qx "$p" <<<"$used" || [[ -n $(ss -Htln "sport = :$p" 2>/dev/null) ]]; do p=$((p + 1)); done
  echo "$p"
}

# A VM made before ports were its own (all had 2222): one given now, at its first start since
ensure_port() {
  local SSH_PORT MEM CPUS ISO SSH_USER; read_conf "$1"
  [[ -n $SSH_PORT ]] && return 0
  conf "$1" SSH_PORT "$(free_port "$1")"
  ssh_sync
}

# ~/.ssh/config.d/garage from the VMs' vm.conf, written whole each time (create, rename, delete, a user or port
# changed), so it can't drift from them. Written to a new file, then renamed over the old one; 600 by garage-ctl's umask
ssh_sync() {
  local d n out SSH_PORT MEM CPUS ISO SSH_USER
  out="# Garage's VMs, so that \`ssh NAME\` reaches one. Garage writes this file: a change made here goes."$'\n'
  for d in "$ROOT"/*/; do
    n=$(basename "$d")
    [[ -f $d/vm.conf ]] && good_name "$n" || continue
    read_conf "$n"
    [[ -n $SSH_PORT ]] || continue
    out+=$'\n'"Host $n"$'\n'"    HostName 127.0.0.1"$'\n'"    Port $SSH_PORT"$'\n'
    [[ -n $SSH_USER ]] && out+="    User $SSH_USER"$'\n'
    out+="    HostKeyAlias $n"$'\n'
  done
  mkdir -p -m 700 "$SSH_DIR" "$SSH_DIR/config.d"
  printf '%s' "$out" > "$SSH_CONF.new" && mv "$SSH_CONF.new" "$SSH_CONF"
  ssh_include
}

# The Include line, first in ~/.ssh/config: ssh reads an Include after a Host line as part of that block. Added once and
# never touched again; the rest of the file stays as it was. Through a symlink (a config kept in dotfiles) the file it
# points to changes, not the link
ssh_include() {
  local f; f=$(readlink -f "$SSH_DIR/config")
  if [[ -f $f ]]; then
    grep -qiE '^[[:space:]]*Include[[:space:]].*config\.d/garage([[:space:]]|$)' "$f" && return 0
    { printf 'Include config.d/garage\n\n'; cat "$f"; } > "$f.garage-new"
    chmod 600 "$f.garage-new" && mv "$f.garage-new" "$f"
  else
    printf 'Include config.d/garage\n' > "$f"
  fi
}

# A deleted VM's host key out of known_hosts: a new VM of the same name has a new one, and ssh would warn of an attack
ssh_forget() {
  local kh=$SSH_DIR/known_hosts
  [[ -f $kh ]] && ssh-keygen -F "$1" -f "$kh" >/dev/null 2>&1 && ssh-keygen -R "$1" -f "$kh" >/dev/null 2>&1
  return 0
}
