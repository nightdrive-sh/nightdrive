import QtQuick
import Quickshell
import qs

// Tailscale: on/off, this machine and the other machines on the network, online and offline. A click on a machine opens a
// terminal with `ssh MACHINE` (its MagicDNS name; the user name is ssh's own: the local one, or ~/.ssh/config's User);
// the copy button at the row's right edge copies its IP address. Phones, tablets and offline machines copy on a click too.
// A shared tailnet: other users' machines wait behind a closed row with their owner's name, and copy on a click.
// On/off requires running this once: sudo tailscale set --operator=$USER
// Not logged in (a new install): Log in starts the login and opens its link in the browser (./login).
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 8

    property bool running: LastState.tailscale
    onRunningChanged: LastState.tailscale = running
    property bool needsLogin: false
    property string selfIp: ""
    property string selfName: ""
    property var peers: []           // this user's own machines: [{ host, ip, online, os }]
    property var others: []          // other users' machines, by owner: [{ owner, peers: [...] }]
    property string openOwner: ""    // the other user whose machines are shown
    property string message: ""
    property string copied: ""
    signal close()

    function refresh() { statusProc.running = true }
    function toggle() {
        if (m.needsLogin && !m.running) { m.login(); return }   // tailscale up would only wait for the login
        m.message = ""
        toggleProc.script = m.running ? "tailscale down" : "tailscale up"
        toggleProc.running = true
    }
    // Detached, with its error as a notification: the browser takes the focus and the menu closes
    function login() {
        Quickshell.execDetached(["bash", "-c", 'msg=$("$1") || notify-send Tailscale "$msg"', "_",
                                 Qt.resolvedUrl("login").toString().replace(/^file:\/\//, "")])
        m.close()
    }
    // ssh exits 255 when it couldn't connect: the terminal stays open on its error until a key, else it closes on logout
    function ssh(host) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/terminal", "--", "bash", "-c",
                                 'ssh "$1"; [ $? = 255 ] && read -rsn1 -p "Press a key to close"', "_", host])
        m.close()
    }
    // Where ssh makes sense: an online computer, not a phone or a tablet (Tailscale's OS: iOS covers the iPad)
    function sshable(p) { return p.online && p.host !== "" && !/^(ios|android|tvos)$/i.test(p.os || "") }
    function copy(ip) {
        Quickshell.execDetached(["wl-copy", ip])
        m.copied = ip
        copiedTimer.restart()
    }
    Component.onCompleted: refresh()
    Timer { interval: 3000; repeat: true; running: true; onTriggered: m.refresh() }
    Timer { id: copiedTimer; interval: 1500; onTriggered: m.copied = "" }

    Sh {
        id: statusProc
        command: ["tailscale", "status", "--json"]
        onResult: text => {
            let j
            // User ids are 17 digits, past what a JS number holds: as strings, so the User table finds them
            try { j = JSON.parse(text.replace(/"UserID":\s*(\d+)/g, '"UserID":"$1"')) } catch (e) { m.running = false; m.peers = []; return }
            m.running = j.BackendState === "Running"
            m.needsLogin = j.BackendState === "NeedsLogin"
            m.selfIp = ((j.Self || {}).TailscaleIPs || [""])[0]
            // Machine name from the admin console (MagicDNS name), not the OS hostname: they differ after a rename
            const name = p => ((p.DNSName || "").split(".")[0]) || p.HostName || ""
            m.selfName = name(j.Self || {})
            const me = (j.Self || {}).UserID
            const arr = [], byOwner = {}
            for (const k in (j.Peer || {})) {
                const p = j.Peer[k]
                const peer = { host: name(p), ip: (p.TailscaleIPs || [""])[0], online: !!p.Online, os: p.OS }
                if (!me || !p.UserID || p.UserID === me) { arr.push(peer); continue }
                const u = (j.User || {})[p.UserID] || {}
                const owner = u.DisplayName || u.LoginName || "Another user"
                ;(byOwner[owner] = byOwner[owner] || []).push(peer)
            }
            const order = (a, b) => (b.online - a.online) || a.host.localeCompare(b.host)
            arr.sort(order)
            m.peers = arr
            m.others = Object.keys(byOwner).sort().map(o => ({ owner: o, peers: byOwner[o].sort(order) }))
        }
    }
    Sh {
        id: toggleProc
        onResult: text => {
            if (toggleProc.exitCode !== 0)
                m.message = /denied|operator/i.test(text) ? "Permission denied. Run once: sudo tailscale set --operator=$USER"
                                                          : text.trim().split("\n").pop()
            m.refresh()
        }
    }

    MenuHeader {
        width: parent.width
        title: "Tailscale"
        showToggle: true
        checked: m.running
        onToggled: m.toggle()
    }

    MenuRow {
        visible: m.running && m.selfIp !== ""
        width: parent.width
        height: visible ? 34 : 0
        icon: "laptop-minimal-check"   // this machine, connected
        tinted: true
        label: m.selfName        // this machine
        detail: m.copied === m.selfIp ? "copied" : m.selfIp
        checkIcon: m.copied === m.selfIp ? "check" : "copy"   // in line with the other machines' copy buttons
        checkIconSize: 13
        onClicked: m.copy(m.selfIp)
    }
    MenuNote {
        visible: !m.running
        text: m.needsLogin ? "Not logged in" : "Tailscale is off"
    }
    MenuButton {
        visible: m.needsLogin && !m.running
        width: parent.width
        icon: "log-in"
        label: "Log in"
        onClicked: m.login()
    }

    // The other machines: online ones first, then offline ones (dimmed) under their own title
    Repeater {
        model: m.running ? [{ title: "Online", online: true }, { title: "Offline", online: false }] : []
        delegate: Column {
            id: sec
            required property var modelData
            readonly property var list: m.peers.filter(p => p.online === modelData.online)
            visible: list.length > 0
            width: m.width
            spacing: 2
            MenuSection { title: sec.modelData.title; bottomPadding: 4 }
            Repeater {
                model: sec.list
                delegate: TailscalePeer { menu: m; width: sec.width }
            }
        }
    }

    // Other users' machines (a shared tailnet): one closed row per owner, a click opens it (one at a time)
    Column {
        visible: m.running && m.others.length > 0
        width: m.width
        spacing: 2
        MenuSection { title: "Other users"; bottomPadding: 4 }
        Repeater {
            model: m.running ? m.others : []
            delegate: Column {
                id: other
                required property var modelData
                readonly property bool open: m.openOwner === modelData.owner
                width: m.width
                spacing: 2
                MenuRow {
                    width: parent.width
                    icon: "user-round"
                    label: other.modelData.owner
                    detail: other.modelData.peers.length + (other.modelData.peers.length === 1 ? " device" : " devices")
                    checkIcon: other.open ? "chevron-down" : "chevron-right"
                    checkIconSize: 13
                    onClicked: m.openOwner = other.open ? "" : other.modelData.owner
                }
                Repeater {
                    model: other.open ? other.modelData.peers : []
                    delegate: TailscalePeer { menu: m; width: other.width; sshAllowed: false }
                }
            }
        }
    }

    MenuNote {
        visible: m.message !== ""
        variant: "danger"
        text: m.message
    }

    MenuButton {
        width: parent.width
        gap: 10   // no divider above it: the room sets it apart
        icon: "external-link"
        label: "Admin console"
        onClicked: { Quickshell.execDetached(["xdg-open", "https://login.tailscale.com/admin/machines"]); m.close() }
    }
}
