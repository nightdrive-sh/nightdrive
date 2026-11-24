import QtQuick
import Quickshell
import qs

// Network Drives: each drive and its state (bin/netdrive list --json); a click opens a mounted one in Files and starts
// one that isn't. Connect again restarts the drives that are on (one waiting for its host tries at once instead of
// after its pause).
Column {
    id: m
    width: parent ? parent.width : 320
    spacing: 8
    signal close()

    readonly property string cmdPath: Qt.resolvedUrl("bin/netdrive").toString().replace(/^file:\/\//, "")
    property var drives: []          // netdrive list --json's rows
    property string error: ""
    readonly property var stateText: ({ mounted: "", connecting: "connecting", failed: "failed", off: "off",
                                        stale: "not connected" })
    readonly property bool trouble: drives.some(d => d.state === "failed" || d.state === "stale"
                                                     || (d.enabled && d.state !== "mounted"))

    // A script, not a command: Sh sets exitCode only for one (the path is the plugin's, with no quote in it)
    function run(args) { cmd.script = "'" + m.cmdPath + "' " + args.join(" ") + " 2>&1"; cmd.running = true }
    function iconOf(d) {
        if (d.state !== "mounted") return "cloud-off"
        return d.uploads ? "cloud-upload" : "hard-drive"
    }
    function detailOf(d) {
        if (d.state !== "mounted") return m.stateText[d.state] || d.state
        if (d.failed_uploads) return d.failed_uploads + " failed to upload"
        if (d.uploads) return d.uploads + " to upload"
        return d.read_only ? "read only" : ""
    }

    Component.onCompleted: list.running = true
    Timer { interval: 3000; repeat: true; running: true; onTriggered: list.running = true }

    Sh {
        id: list
        command: [m.cmdPath, "list", "--json"]
        onResult: text => {
            try { m.drives = JSON.parse(text).drives; m.error = "" } catch (e) { m.error = text.trim() || "netdrive list failed" }
        }
    }
    Sh {
        id: cmd
        onResult: text => { if (cmd.exitCode !== 0) m.error = text.trim(); list.running = true; TopBar.refresh("netdrive") }
    }

    MenuHeader { width: parent.width; title: "Network Drives" }

    MenuNote { variant: "danger"; text: m.error }
    MenuNote { text: m.drives.length ? "" : "No drives yet: netdrive add NAME --ssh HOST in a terminal (the plugin's page says more)." }

    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: m.drives
            delegate: Column {
                required property var modelData
                width: m.width
                spacing: 2
                MenuRow {
                    width: parent.width
                    icon: m.iconOf(modelData)
                    label: modelData.name
                    detail: m.detailOf(modelData)
                    danger: modelData.state === "failed" || modelData.failed_uploads > 0
                    // A mounted drive opens in Files; one that isn't tries to connect again now
                    onClicked: {
                        if (modelData.state !== "mounted") {
                            m.run([modelData.state === "off" ? "start" : "restart", modelData.name]); return
                        }
                        Quickshell.execDetached(["xdg-open", modelData.path]); m.close()
                    }
                }
                // Why it isn't mounted: the service's own line (waiting for its host, how it stopped)
                MenuNote {
                    width: parent.width
                    variant: modelData.state === "failed" ? "warning" : "dim"
                    text: modelData.state !== "mounted" && modelData.detail ? modelData.detail : ""
                }
            }
        }
    }

    MenuButton {
        width: parent.width
        visible: m.trouble
        gap: 10
        icon: "refresh-cw"
        label: "Connect again"
        onClicked: m.run(["restart", "all"])
    }
}
