import QtQuick

// ⌥ + a character key with a Mac layout (#3525). A layout that makes ⌥ level 3 (fi(mac) with lv3:lalt_switch) turns ⌥
// into Mod5, which Qt reads as no modifier at all: ⌥2 arrives as "@" and ⌥F as "đ", with no Alt. Hyprland gives the
// apps Alt for ⌥ + an arrow or ⏎ (hypr/option-keys.lua), but not for a character key: that would take @ from every text
// field. So an app with ⌥ + a character (Inbox's ⌥1 … ⌥8, Mail's ⌥F) keeps one of these, hands it the presses and
// releases where those keys are read (the level-3 ⌥ itself comes as Qt.Key_AltGr), and asks key(e) and alt(e).
// AltGr on a PC layout counts as ⌥ too: where these keys are read, it types nothing.
QtObject {
    property bool held: false

    // The keys' places as Linux numbers them (evdev + 8: Qt's nativeScanCode), on a QWERTY keyboard, with the
    // character each types alone: a level-3 key is known by its place, as its own character is another
    readonly property var places: {
        const p = {}
        "1234567890".split("").forEach((ch, i) => p[10 + i] = ch)
        "qwertyuiop".split("").forEach((ch, i) => p[24 + i] = ch)
        "asdfghjkl".split("").forEach((ch, i) => p[38 + i] = ch)
        "zxcvbnm".split("").forEach((ch, i) => p[52 + i] = ch)
        return p
    }

    function pressed(e) {
        if (e.key === Qt.Key_AltGr) { held = true; return }
        // A release that went elsewhere (another window had the keys) leaves held on: a key that types its own
        // character says ⌥ isn't down
        const ch = places[e.nativeScanCode]
        if (held && ch !== undefined && e.text.toLowerCase() === ch) held = false
    }
    function released(e) {
        if (e.key === Qt.Key_AltGr) held = false
    }
    // The level-3 ⌥ is down for this character key
    function level3(e) {
        return held && places[e.nativeScanCode] !== undefined && e.text.toLowerCase() !== places[e.nativeScanCode]
    }
    // ⌥ is down: Alt as Qt sees it, or the level-3 ⌥ on a character key
    function alt(e) {
        return (e.modifiers & Qt.AltModifier) !== 0 || level3(e)
    }
    // The key as Qt.Key_*, a level-3 ⌥'s character key by its place: ⌥2's "@" is Qt.Key_2, ⌥F's "đ" Qt.Key_F
    function key(e) {
        if (!level3(e)) return e.key
        const ch = places[e.nativeScanCode]
        return ch >= "0" && ch <= "9" ? Qt.Key_0 + Number(ch) : Qt.Key_A + ch.charCodeAt(0) - 97
    }
}
