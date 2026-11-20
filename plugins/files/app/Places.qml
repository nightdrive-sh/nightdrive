import QtQuick
import Quickshell.Io

// The sidebar's rows (lib/cli.py places): Files' own group (pinned.py: home and home's folders until the user changes
// it), the bookmarks (GTK's), the disks and the trash, as one list entries
// [{ kind: place|bookmark|device|trash, name, path, glyph, device, unmount, gap }] that the keys walk through as the
// pointer does; and as its three parts, which the sidebar shows with a drop slot for an empty group between them.
// Read at the start, after a change that can move them (a bookmark, the trash), and when the mounts change:
// /proc/self/mounts is read every few seconds (a cat, no Python), the places only when it differs.
QtObject {
    id: root
    required property var app              // the window: helper, active
    property var data: ({ pinned: [], bookmarks: [], devices: [], trash: 0, downloads: "" })
    readonly property var pinnedRows: data.pinned.map(p => ({ kind: "place", name: p.name, path: p.path, glyph: p.glyph }))
    readonly property var bookmarkRows: data.bookmarks.map((b, i) => ({ kind: "bookmark", name: b.name, path: b.path,
                                                                        glyph: b.missing ? "folder-x" : "bookmark", gap: i === 0 }))
    readonly property var otherRows: {
        const out = []
        data.devices.forEach((d, i) => out.push({ kind: "device", name: d.name, path: d.path, device: d.device, glyph: d.glyph, unmount: d.unmount, gap: i === 0 }))
        out.push({ kind: "trash", name: "Trash", path: "", glyph: "trash-2", count: data.trash, gap: true })
        return out
    }
    readonly property var entries: pinnedRows.concat(bookmarkRows, otherRows)
    function bookmarked(path) { return data.bookmarks.some(b => b.path === path) }

    readonly property Process reader: Process {
        command: ["python3", root.app.helper, "places"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.data = JSON.parse(text) } catch (e) { console.warn("places: " + e) } }
        }
    }
    function refresh() { if (!reader.running) reader.running = true }

    property string mounts: ""
    readonly property Process mountsReader: Process {
        command: ["cat", "/proc/self/mounts"]
        stdout: StdioCollector {
            onStreamFinished: { if (root.mounts && text !== root.mounts) root.refresh(); root.mounts = text }
        }
    }
    readonly property Timer mountsTimer: Timer {
        interval: 3000; repeat: true; running: true
        onTriggered: root.mountsReader.running = true
    }
    Component.onCompleted: { refresh(); mountsReader.running = true }
}
