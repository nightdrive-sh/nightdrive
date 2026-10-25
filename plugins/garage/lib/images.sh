# Ready-made disk images for new VMs (share/images.json, by the host's architecture: lib/arch.sh's ARCH), for
# bin/garage-ctl (sourced after its helpers and lib/firstboot.sh). Fedora makes a Minimal image (raw.xz) for aarch64
# only, so x86_64's is Cloud Base (qcow2): both boot without an installer. One is downloaded once, in the background,
# over HTTPS only, and checked against its sha256 in images.json; each new VM's disk is then made from it: unpacked,
# converted to qcow2 and grown to its size, with its first boot's user (lib/firstboot.sh). In images/ beside the VMs:
#   FILE                 a checked image
#   FILE.part, FILE.pid  one on its way (curl, resumed where it stopped), and its download's process
#   FILE.error           why the last try failed

IMAGES_JSON=$(cd "$(dirname "${BASH_SOURCE[0]}")/../share" && pwd)/images.json
IMG_DIR=$ROOT/images

image() { jq -ce --arg id "$1" --arg a "$ARCH" '.[$a][]? | select(.id == $id)' "$IMAGES_JSON" || die "No image $1 for $ARCH"; }
image_file() { echo "$IMG_DIR/$(basename "$(jq -r .url <<<"$1")")"; }
fetching() { local p; p=$(cat "$1.pid" 2>/dev/null) && kill -0 "$p" 2>/dev/null; }

# JSON: [{ id, name, about, size, minDisk (GB, the image's own), state: ready | downloading | failed | none,
#         done: bytes so far, error }]
images() {
  local e f state got err
  jq -c --arg a "$ARCH" '.[$a][]?' "$IMAGES_JSON" | while read -r e; do
    f=$(image_file "$e"); state=none; got=0; err=""
    if [[ -f $f ]]; then state=ready
    elif fetching "$f"; then state=downloading; got=$(stat -c %s "$f.part" 2>/dev/null || echo 0)
    elif [[ -f $f.error ]]; then state=failed; err=$(cat "$f.error")
    fi
    jq -c --arg state "$state" --argjson got "$got" --arg err "$err" \
       '{ id, name, about, size, minDisk, state: $state, done: $got, error: $err }' <<<"$e"
  done | jq -sc .
}

# Its download, started in the background (garage-ctl fetch-run), unless it is there or on its way
fetch() {
  local e f; e=$(image "$1"); f=$(image_file "$e")
  [[ -f $f ]] || fetching "$f" && return 0
  mkdir -p "$IMG_DIR"; rm -f "$f.error"
  setsid -f "$0" fetch-run "$1" </dev/null >/dev/null 2>&1
}
fetch_run() {
  local e f url sum; e=$(image "$1"); f=$(image_file "$e"); url=$(jq -r .url <<<"$e")
  echo $$ > "$f.pid"
  failed() { echo "$*" > "$f.error"; rm -f "$f.pid"; exit 1; }
  # HTTPS all the way, redirects to a mirror too
  curl -fsSL --proto =https --proto-redir =https --retry 3 -C - -o "$f.part" "$url" \
    || failed "The download stopped: try again, it goes on from there"
  # The hash is images.json's, taken from the release's CHECKSUM file once its Fedora signature checked out (gpgv): a
  # CHECKSUM fetched now would come from the same mirror as the image, and a bad mirror would serve a matching one
  sum=$(jq -r .sha256 <<<"$e")
  [[ $(sha256sum "$f.part" | cut -d' ' -f1) == "$sum" ]] || { rm -f "$f.part"; failed "It didn't match its checksum, so it was deleted: try again"; }
  mv "$f.part" "$f"; rm -f "$f.pid"
}

# unpack IMAGE DISK: the image as the VM's own qcow2. A raw.xz unpacked sparse (dd), as it is mostly empty, then
# converted; a qcow2 converted as it is (its own copy, compacted). Each with its format named (-f), not guessed from
# what the file says, and a qcow2 without a backing file: either could make the copy read another file of the host's
unpack() {
  case $1 in
    *.raw.xz) xz -dcT0 "$1" | dd of="$2.raw" conv=sparse bs=1M status=none &&
              qemu-img convert -f raw -O qcow2 "$2.raw" "$2" && rm "$2.raw" ;;
    *.qcow2)  [[ $(qemu-img info -f qcow2 --output=json "$1" | jq -r '.["backing-filename"] // ""') == "" ]] ||
                { echo "${1##*/} has a backing file" >&2; return 1; }
              qemu-img convert -f qcow2 -O qcow2 "$1" "$2" ;;
    *)        echo "Unknown image format: ${1##*/}" >&2; return 1 ;;
  esac
}

# create-image NAME ID MEM_GB DISK_GB CPUS USER, the password on stdin (not in ps)
create_image() {
  (($# >= 6)) || die "create-image NAME ID MEM_GB DISK_GB CPUS USER (the password on stdin)"
  local name=$1 id=$2 mem=$3 disk=$4 cpus=$5 user=$6 pass e f d
  e=$(image "$id"); f=$(image_file "$e"); d=$(dir "$name")
  [[ -e $d ]] && die "$name exists already"
  [[ -f $f ]] || die "$(jq -r .name <<<"$e") isn't downloaded yet"
  sizes "$mem" "$disk" "$cpus"
  need_qemu
  local min; min=$(jq -r '.minDisk // 0' <<<"$e")
  ((disk >= min)) || die "Disk: at least $min GB for $(jq -r .name <<<"$e")"
  IFS= read -r pass || true
  mkdir -p "$d"
  # The folder goes if any of it fails. The tools' own lines ("cp: error writing '…/vars.raw': No space left on device")
  # are kept from the window's error line: it gets ours, with only why from the last of theirs
  local log; log=$(mktemp)
  if ! { unpack "$f" "$d/disk.qcow2" &&
         qemu-img resize -q "$d/disk.qcow2" "${disk}G" &&
         cp "$FW_VARS" "$d/vars.raw" &&
         printf 'MEM=%s\nCPUS=%s\nISO=""\n' $((mem * 1024)) "$cpus" > "$d/vm.conf"; } 2>"$log"; then
    local why; why=$(grep . "$log" | tail -1 | sed 's/.*: //')
    rm -rf "$d" "$log"; die "$name couldn't be made from $(jq -r .name <<<"$e")${why:+: $why}"
  fi
  rm -f "$log"
  ( firstboot_creds "$name" "$user" "$pass" ) || { rm -rf "$d"; exit 1; }
}
