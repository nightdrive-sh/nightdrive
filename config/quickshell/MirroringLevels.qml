import QtQuick
import Quickshell

// Screen Mirroring in the launcher (AirPlay with doubletake; the mirroring plugin, plugins/mirroring): the AirPlay
// devices' rows under Settings › Other displays (DisplayLevels.qml asks for mirrorRows through Launcher.qml) and the
// pairing code's page, Screen Mirroring › Code. Launcher.qml asks it like its other Levels files (levels, titles, parents,
// items, activate, footer, entered) and enters it with Display's levels too. Split from SystemLevels.qml (#1937).
Item {
    id: s
    property var launcher: null

    readonly property var inputs: ["mirrorpin"]   // text fields: ⌘⇧V pastes into them (ClipPicker)
    readonly property var levels: ["mirrorpin"]
    readonly property var titles: ({ mirrorpin: "Screen Mirroring › Code" })
    readonly property var parents: ({ mirrorpin: "otherdisplays" })
    readonly property string level: launcher ? launcher.level : ""

    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (level === "mirrorpin") return query !== "" ? "Enter: pair" : ""
        if (cur.kind === "mirrordev") return "Enter: " + (cur.ip === mirrorIp && mirrorState !== "idle" ? "stop mirroring" : "mirror the screen here")
        return ""
    }
    function opened() {}
    function entered(level) {
        if (level === "mirrorpin" || level === "display" || level === "otherdisplays") mirrorProc.running = true
    }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "mirrorpin") return [{ kind: "mirrorcode", name: "Pair with " + (mirrorName || "the receiver"), glyph: "key-round",
                                             summary: launcher.query === "" ? "type the code on the TV" : undefined, dimmed: launcher.query === "" }]
        return []
    }

    // Enter on a row. Returns true when the row was one of ours.
    function activate(it) {
        if (it.kind === "mirrordev") {
            if (it.ip === mirrorIp && mirrorState !== "idle") { sel(); mirrorState = "idle"; Quickshell.execDetached([mirrorScript, "stop"]); return true }
            // The share window can't be clicked under the launcher (it takes the keyboard): close it; a code request reopens it
            launcher.open = false
            Quickshell.execDetached([mirrorScript, "connect", it.ip])
            return true
        }
        if (it.kind === "mirrorcode") {
            if (launcher.query === "") { launcher.shakeNow(); return true }
            Quickshell.execDetached([mirrorScript, "pin", launcher.query.trim()])
            launcher.open = false           // the share window comes next
            return true
        }
        return false
    }

    // Rows for Settings › Other displays (DisplayLevels.qml). Nothing while the plugin isn't installed
    // or is off.
    readonly property string mirrorScript: Quickshell.env("HOME") + "/.local/bin/mirroring"
    property bool mirrorAvail: false
    property var mirrorDevices: []   // [{ name, model, ip }]
    property string mirrorState: "idle"   // idle | connecting | pin_required | streaming
    property string mirrorIp: ""
    readonly property string mirrorName: (mirrorDevices.find(d => d.ip === mirrorIp) || {}).name || ""
    function mirrorRows() {
        if (!mirrorAvail) return []
        const r = [{ kind: "header", name: "Screen Mirroring" }]
        if (mirrorDevices.length === 0) r.push({ kind: "hint", name: "Looking for AirPlay devices…" })
        for (const d of mirrorDevices) {
            const mine = d.ip === mirrorIp && mirrorState !== "idle"
            r.push({ kind: "mirrordev", name: d.name, ip: d.ip, extra: "airplay cast mirror " + d.model,
                     glyph: /STR-|receiver|HomePod|AudioAccessory|speaker/i.test(d.name + " " + d.model) ? "speaker" : "tv",
                     summary: !mine ? "AirPlay · mirror" : mirrorState === "streaming" ? "mirroring" : mirrorState === "pin_required" ? "waiting for the code" : "connecting…",
                     trailGlyph: mine && mirrorState === "streaming" ? "check" : undefined,
                     active: mine && mirrorState === "streaming" })   // in use: Settings › Other displays' summary
        }
        return r
    }
    Timer { interval: 2000; repeat: true; running: s.launcher !== null && s.launcher.open && (s.level === "otherdisplays" || s.level === "mirrorpin"); onTriggered: mirrorProc.running = true }
    Sh {
        id: mirrorProc
        script: 'c="$HOME/.local/bin/doubletake-ctl"; [ -x "$c" ] || exit 0; "$c" status; echo; "$c" devices; echo; printf "{\\"self\\": \\"%s\\"}\\n" "$(hostname -I)"'
        onResult: text => {
            const parts = text.trim().split(/\n(?=\{)/)   // three JSON objects: status, devices, and this computer's addresses
            let st = null, dev = null
            let self = []
            try { st = JSON.parse(parts[0]); dev = JSON.parse(parts[1]); self = JSON.parse(parts[2]).self.trim().split(/\s+/) } catch (e) {}
            const avail = Plugins.has("mirroring") && st !== null && st.ok === true   // off: hidden, though doubletake runs
            // Only what can show a screen: not this computer's own receiver (AirPlay Receiver), nor a speaker. AirPlay's
            // listing doesn't say which can show video, so speakers are told by their model: Sonos (One, Era 300…),
            // HomePods, receivers
            const speaker = /^(One|One SL|Era \d+|Five|Play:\d|Move|Roam|Beam|Arc|Ray|Sub|Port|Amp|Connect)\b|HomePod|AudioAccessory|STR-/i
            const devices = dev && dev.devices ? dev.devices.filter(d => !self.includes(d.ip) && !speaker.test(d.model || ""))
                                                            .map(d => ({ name: d.name, model: d.model || "", ip: d.ip })) : []
            const state = st && st.state ? st.state : "idle"
            const ip = st && st.device_ip ? st.device_ip : ""
            if (avail === s.mirrorAvail && state === s.mirrorState && ip === s.mirrorIp && JSON.stringify(devices) === JSON.stringify(s.mirrorDevices)) return
            s.sel()
            s.mirrorAvail = avail; s.mirrorState = state; s.mirrorIp = ip; s.mirrorDevices = devices
        }
    }
}
