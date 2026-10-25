import QtQuick
import Quickshell

// The launcher's System › About Nightdrive: the release this desktop is at, its update channel, the computer, and links to
// the website and the repo. Found by searching "version" or "about" too (its row's extra in Launcher.qml's statics.system).
Item {
    id: a
    property var launcher: null

    readonly property var levels: ["about"]
    readonly property var titles: ({ about: "System › About Nightdrive" })
    readonly property var parents: ({ about: "system" })
    readonly property string repoUrl: "https://github.com/nightdrive-sh/nightdrive"

    // nightdrive version's line ("Nightdrive 0.5.0, and 3 changes since (dev channel, 2249eb6)"), the OS and the machine.
    // Sh merges stderr into the output, so the OS and machine lines keep theirs out: an error there would be read as the
    // line (and `< file 2>/dev/null` doesn't do it, the < fails before the 2> is set up).
    // The machine: the device tree's model on Arm boards and Macs (Asahi), else DMI on PCs and VMs ("QEMU Virtual
    // Machine", not "QEMU QEMU Virtual Machine"), with a self-built PC's placeholders swapped for its board's name.
    property var info: null
    Sh {
        id: infoProc
        script: '"$HOME/.local/bin/nightdrive" version
                 ( . /etc/os-release && echo "$NAME $VERSION_ID" ) 2>/dev/null || echo
                 {
                     m=$(tr -d "\\0" < /sys/firmware/devicetree/base/model)
                     if [ -z "$m" ]; then
                         d=/sys/class/dmi/id; v=$(cat $d/sys_vendor); p=$(cat $d/product_name)
                         case "$v$p" in *"To Be Filled"*|*"Default string"*|*"System manufacturer"*|*"System Product Name"*)
                             v=$(cat $d/board_vendor); p=$(cat $d/board_name) ;; esac
                         case "$p" in "$v"*) m=$p ;; *) m="$v $p" ;; esac
                     fi
                     m=$(echo $m)
                     echo "${m:-Unknown}"
                 } 2>/dev/null'
        onResult: text => {
            const f = text.split("\n")
            const m = (f[0] || "").match(/^Nightdrive(?: (\S+?))?,?(?: and (\d+) changes? since| no release yet)? \((\S+) channel(?:, (\w+))?\)/)
            a.info = { line: (f[0] || "").trim(), version: m && m[1] ? m[1] : "", changes: m && m[2] ? Number(m[2]) : 0,
                       channel: m ? m[3] : "", commit: m && m[4] ? m[4] : "", os: (f[1] || "").trim(), machine: (f[2] || "").trim() }
        }
    }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        return cur.kind === "stat" ? "Enter: copy" : ""
    }
    function opened() {}
    function entered(level) { if (level === "about") infoProc.running = true }

    function link(name, glyph, url, extra) { return { kind: "action", name: name, glyph: glyph, cmd: ["xdg-open", url], extra: extra || "" } }

    function items(level, q) {
        if (level !== "about") return []
        const i = info
        const rows = [{ kind: "header", name: "Nightdrive" }]
        if (!i) rows.push({ kind: "hint", name: "Loading…" })
        else {
            // On dev the release is behind the code: the changes since it and the commit say where it really is
            rows.push({ kind: "stat", name: "Version", glyph: "tag", copy: i.line,
                        summary: (i.version || "no release yet") + (i.changes > 0 ? " + " + i.changes + " change" + (i.changes === 1 ? "" : "s") : "") })
            if (i.channel) rows.push({ kind: "stat", name: "Update channel", glyph: "git-branch", copy: i.channel,
                                       summary: i.channel === "dev" ? "development" : i.channel })
            if (i.commit) rows.push({ kind: "stat", name: "Commit", glyph: "git-commit-horizontal", copy: i.commit, summary: i.commit })
        }
        // nightdrive update check's count (every 6 h): the same Update as System's
        if (launcher.updates > 0) rows.push(launcher.statics.system.find(t => t.name === "Update"))
        if (i && (i.os || i.machine)) {
            rows.push({ kind: "header", name: "This computer" })
            if (i.os) rows.push({ kind: "stat", name: "System", glyph: "server", copy: i.os, summary: i.os })
            if (i.machine) rows.push({ kind: "stat", name: "Computer", glyph: "laptop", copy: i.machine, summary: i.machine })
        }
        // A search drops the headers, as in the statics
        return { all: rows.concat([
            { kind: "header", name: "Links" },
            link("nightdrive.sh", "globe", "https://nightdrive.sh/"),
            link("Documentation", "book-open", "https://nightdrive.sh/docs/"),
            link("Changelog", "scroll-text", "https://nightdrive.sh/changelog/"),
            link("Source on GitHub", "code", repoUrl),
            link("Report an issue", "bug", repoUrl + "/issues"),
            link("Email hello@nightdrive.sh", "mail", "mailto:hello@nightdrive.sh")
        ]).map(t => ({ item: t, text: t.kind === "header" || t.kind === "hint" ? "" : t.name, extra: (t.summary || "") + " " + (t.extra || "") })) }
    }
    function activate(it) { return false }
}
