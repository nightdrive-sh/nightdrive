.pragma library
// The device list shared by the top bar's BluetoothMenu and the launcher's BluetoothLevels: the bluetoothctl script
// that lists them, its parsing, their order and their icons. Split from both (#3527).

// How long Scan for devices looks. 20 s was too short: an Xbox controller put in pairing mode after pressing Scan showed
// up a few seconds before the scan ended, and BlueZ drops a device nobody paired as soon as the scan stops (#3527)
var SCAN_SECONDS = 60
// A device this strong (dBm) is near the computer, most likely the one in the user's hand: it goes first among the
// devices not paired, ahead of a busy street's TVs and laptops, which otherwise pushed it past the menu's 8 rows
var NEAR_RSSI = -65

// One line per device: mac|connected|paired|battery|named|rssi|icon|name (the name last: it may hold a "|")
var LIST_SCRIPT =
    'systemctl is-active -q bluetooth 2>/dev/null || exit 0\n' +
    'bluetoothctl devices | sed "s/\\x1b\\[[0-9;]*m//g" | while read -r _ mac name; do\n' +
    '  info=$(bluetoothctl info "$mac")\n' +
    '  c=$(grep -c "Connected: yes" <<<"$info"); p=$(grep -c "Paired: yes" <<<"$info"); n=$(grep -c "^\\s*Name:" <<<"$info")\n' +
    '  b=$(grep -oP "Battery Percentage: 0x\\w+ \\(\\K[0-9]+" <<<"$info")\n' +
    '  r=$(grep -oP "RSSI: 0x\\w+ \\(\\K-?[0-9]+" <<<"$info"); i=$(grep -oP "^\\s*Icon: \\K\\S+" <<<"$info")\n' +
    '  echo "$mac|$c|$p|$b|$n|$r|$i|$name"\n' +
    'done'

// The script's output → [{ mac, connected, paired, battery, named, near, icon, name }], in the menu's order.
// seen: { mac: true } of the devices found near during this scan, kept by the caller, so a device stays near once its
// signal was strong: BlueZ reports RSSI only while the device advertises, and a list that reorders itself every
// refresh would move the row under the pointer
function parse(text, seen) {
    const arr = []
    for (const line of text.split("\n")) {
        const f = line.split("|")
        if (f.length < 8) continue
        const rssi = f[5] !== "" ? parseInt(f[5]) : NaN
        if (rssi >= NEAR_RSSI) seen[f[0]] = true
        arr.push({ mac: f[0], connected: f[1] !== "0", paired: f[2] !== "0", battery: f[3], named: f[4] !== "0",
                   near: seen[f[0]] === true, icon: f[6], name: f.slice(7).join("|") })
    }
    arr.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || (b.near - a.near) || a.name.localeCompare(b.name))
    return arr
}

// Nameless devices (only an address: mostly nearby phones, Macs and AirTags with a changing random address) are hidden
// unless paired; "Show hidden devices" lists them too
function isHidden(d) { return !d.named && !d.paired && !d.connected }

// BlueZ's Icon (from the device's class or appearance) when it has one, else a guess from the name
var ICONS = {
    "input-gaming": "gamepad-2", "input-mouse": "mouse", "input-tablet": "pen-tool", "input-keyboard": "keyboard",
    "audio-headphones": "headphones", "audio-headset": "headphones", "audio-card": "speaker",
    "phone": "smartphone", "computer": "laptop", "video-display": "tv", "camera-video": "video", "camera-photo": "camera",
    "printer": "printer", "multimedia-player": "music"
}
function iconFor(d) {
    if (ICONS[d.icon]) return ICONS[d.icon]
    const name = d.name
    return /head|buds|airpods|wh-|wf-|sony/i.test(name) ? "headphones"
         : /mouse|mx |trackpad/i.test(name) ? "mouse"
         : /keyboard|keys/i.test(name) ? "keyboard"
         : /controller|gamepad|xbox|dualsense|dualshock|joy-con/i.test(name) ? "gamepad-2"
         : /phone|iphone|pixel|galaxy/i.test(name) ? "smartphone"
         : /watch/i.test(name) ? "watch"
         : /speaker|boom|jbl|soundbar/i.test(name) ? "speaker" : "bluetooth"
}
