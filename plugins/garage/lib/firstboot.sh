# A ready-made disk image's first boot (Fedora Minimal or Cloud Base: no installer, no user), for bin/garage-ctl
# (sourced after its helpers and lib/arch.sh): systemd credentials that qemu hands the guest through SMBIOS (type 11). Its
# systemd (256+) makes two units of them (systemd-debug-generator), which run two scripts that come the same way
# (ImportCredential):
#   nightdrive-vm-user    before the login prompt: the user (wheel, so sudo), the VM's name as its hostname, the host's
#                         keymap and timezone, and the host's ssh key, so `ssh -p 2222 localhost` just works
#   nightdrive-vm-agent   once the network is up: sshd and qemu-guest-agent (Shut down, the clock), with dnf
# and Fedora's initial-setup is skipped, as the user is made already (it would ask for one in the VM's window).
# They are written to the VM's folder (firstboot/, a file each, the password only as a hash) and passed at each start
# until the guest agent has shut the VM down once, i.e. both scripts have run (lib/qemu.sh: stop). qemu reads each from
# its file (-smbios path=): given as a value they were in its command line, which any process on the host can read.

# The image's root is 3 GB whatever the disk's size: its partition (the disk's last) and filesystem grow to the disk,
# online. Nice to have too: a layout this doesn't know (LVM) keeps its size
GROW_ROOT='( set -e
src=$(findmnt -no SOURCE /); dev=/dev/$(lsblk -no PKNAME "$src"); part=$(cat "/sys/class/block/${src#/dev/}/partition")
sfdisk --relocate gpt-bak-std "$dev"
echo ", +" | sfdisk --no-reread -q -N "$part" "$dev"
partx -u "$dev"
case $(findmnt -no FSTYPE /) in ext4) resize2fs "$src" ;; xfs) xfs_growfs / ;; btrfs) btrfs filesystem resize max / ;; esac
) || true'

# firstboot_creds NAME USER PASSWORD: firstboot/ in its folder
firstboot_creds() {
  local name=$1 user=$2 pass=$3 d; d=$(dir "$1")
  [[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "User: lower-case letters, digits, - and _, starting with a letter"
  [[ -n $pass ]] || die "A password for $user"
  local hash keymap tz key="" k
  hash=$(printf '%s' "$pass" | openssl passwd -6 -stdin) || die "openssl couldn't hash the password"
  keymap=$(localectl status 2>/dev/null | awk -F': ' '/VC Keymap/ { print $2 }')
  [[ $keymap == "(unset)" ]] && keymap=""
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  for k in "$HOME"/.ssh/id_ed25519.pub "$HOME"/.ssh/id_ecdsa.pub "$HOME"/.ssh/id_rsa.pub; do
    [[ -f $k ]] && { key=$(cat "$k"); break; }
  done

  # The scripts, their values quoted for bash (printf %q)
  local q_user q_home; q_user=$(printf %q "$user"); q_home=$(printf %q "/home/$user")
  local user_script="set -e
id $q_user >/dev/null 2>&1 || useradd -m -G wheel -p $(printf %q "$hash") $q_user"
  [[ -n $key ]] && user_script+="
install -d -m 700 -o $q_user -g $q_user $q_home/.ssh
printf '%s\n' $(printf %q "$key") > $q_home/.ssh/authorized_keys
chown $q_user: $q_home/.ssh/authorized_keys
chmod 600 $q_home/.ssh/authorized_keys"
  # The rest only as nice to have: a keymap the image has no file for mustn't stop the script
  user_script+=$'\n'"hostnamectl set-hostname $(printf %q "$name") || true"
  [[ -n $keymap ]] && user_script+=$'\n'"localectl set-keymap $(printf %q "$keymap") || true"
  [[ -n $tz ]] && user_script+=$'\n'"timedatectl set-timezone $(printf %q "$tz") || true"
  user_script+=$'\n'"$GROW_ROOT"
  user_script+=$'\nmkdir -p /var/lib/nightdrive-vm\ntouch /var/lib/nightdrive-vm/user'
  local agent_script='set -e
dnf install -y openssh-server qemu-guest-agent
systemctl enable --now sshd qemu-guest-agent
mkdir -p /var/lib/nightdrive-vm
touch /var/lib/nightdrive-vm/agent'

  local c=$d/firstboot
  mkdir -m 700 "$c"
  {
    cred nightdrive-vm.user "$user_script"
    cred nightdrive-vm.agent "$agent_script"
    cred systemd.extra-unit.nightdrive-vm-user.service "$(unit user "the first boot's user" \
      "After=systemd-sysusers.service systemd-tmpfiles-setup.service
Before=getty@tty1.service serial-getty@$TTY.service systemd-user-sessions.service")"
    cred systemd.extra-unit.nightdrive-vm-agent.service "$(unit agent "sshd and the guest agent, at the first boot" \
      'Wants=network-online.target
After=network-online.target nightdrive-vm-user.service')"
    cred systemd.unit-dropin.multi-user.target $'[Unit]\nWants=nightdrive-vm-user.service nightdrive-vm-agent.service'
    cred systemd.unit-dropin.initial-setup.service $'[Unit]\nConditionPathExists=/var/lib/nightdrive-vm/initial-setup'
  }
}
# cred NAME VALUE: its file in $c (firstboot_creds'), as SMBIOS type 11 carries it: base64 has no commas or newlines,
# which an OEM string would choke on
cred() { printf 'io.systemd.credential.binary:%s=%s' "$1" "$(printf '%s' "$2" | base64 -w0)" > "$c/$1"; }
# unit ID DESCRIPTION ORDERING: a oneshot running its script once
unit() {
  printf '[Unit]\nDescription=Nightdrive VM: %s\nConditionPathExists=!/var/lib/nightdrive-vm/%s\n%s\n\n' "$2" "$1" "$3"
  printf '[Service]\nType=oneshot\nImportCredential=nightdrive-vm.%s\nExecStart=/bin/bash ${CREDENTIALS_DIRECTORY}/nightdrive-vm.%s\n' "$1" "$1"
}

# qemu's options for them, a file each; none once they're gone
firstboot_args() {
  local f
  for f in "$(dir "$1")"/firstboot/*; do
    [[ -f $f ]] && printf '%s\n' -smbios "type=11,path=$(qv "$f")"
  done
  return 0
}
