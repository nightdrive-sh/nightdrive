import QtQuick
import Quickshell.Io
import "Views.js" as Views

// A task moved in its list (#3507): ⌥↑ ⌥↓ the picked one, or a row dragged to another place (TaskRow's DragHandler).
// Only a list's own view has an order of the user's (Views.orderable); Today and Upcoming are by date.
// The rows change at once, and `cli.py move` writes the new place behind them (lib/order.py: the moved task's file
// alone). The moves run one at a time, in the order made, so ⌥↓ held down ends where the rows show it; the window's
// reads wait until the last is written (shell.qml's load), so a read half-way doesn't put a row back for a moment.
// Each move is one step of ⌘Z (Actions.undos), with no toast: the move itself is what the user sees.
// Declared inside the ListView, so it lives in its content: the drop line is placed in content coordinates.
Item {
    id: root
    required property ListView view
    required property var app           // the window: shown, current, view, helper, load(), say(), reshow()
    required property var ops           // Actions: undos
    required property QtObject c
    readonly property bool can: Views.orderable(app.view)
    readonly property bool busy: queue.length > 0 || runner.running
    property var queue: []              // [argv] still to run

    width: view.width
    height: 0
    z: 2

    function refused() { app.say("Tasks are moved in their own list") }

    // ⌥↑ (-1) ⌥↓ (+1): the picked task one place up or down
    function step(d) {
        if (!can) { refused(); return }
        const from = app.current, to = from + d
        if (from < 0 || to < 0 || to >= app.shown.length) return
        const id = app.shown[from].id
        place(from, to)
        send(["--to", d < 0 ? "up" : "down", "--", id])
    }

    // The rows with the one at `from` now at `to`, picked, before the files say so
    function place(from, to) {
        const rows = app.shown.slice()
        const moved = rows.splice(from, 1)[0]
        rows.splice(to, 0, moved)
        app.reshow(rows, to)
    }

    function send(args) {
        queue = queue.concat([args])
        next()
    }
    function next() {
        if (runner.running || !queue.length) return
        const args = queue[0]
        queue = queue.slice(1)
        runner.command = ["python3", app.helper, "move", "--json"].concat(args)
        runner.running = true
    }
    Process {
        id: runner
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            let d = null
            if (code === 0) try { d = JSON.parse(out.text) } catch (e) {}
            if (d && d.undo) root.ops.undos = root.ops.undos.concat([{ sid: d.undo, id: d.id }]).slice(-root.ops.undoDepth)
            if (!d) {
                // The rest of the queue was worked out from rows that are now wrong: read the files instead
                root.queue = []
                root.app.say(err.text.trim().split("\n").pop() || "That didn't work: tasks log says why.", true)
            }
            if (root.queue.length) { root.next(); return }
            root.app.load()
        }
    }

    // Dragging: the row's index, the gap it would go in (0 … rows), and where the pointer is in the view
    property int from: -1
    property int slot: -1
    property real pointerY: 0
    readonly property bool dragging: from >= 0

    function start(index) {
        if (!can) return
        from = index
        app.current = index
    }
    function over(scenePos) {
        if (!dragging) return
        pointerY = view.mapFromItem(null, scenePos.x, scenePos.y).y
        aim()
    }
    // The gap nearest the pointer: above a row's middle, the gap before it
    function aim() {
        const y = pointerY + view.contentY
        let i = view.indexAt(view.width / 2, y)
        if (i < 0) { slot = y < view.originY + 4 ? 0 : app.shown.length; return }
        const item = view.itemAtIndex(i)
        slot = item && y > item.y + item.height / 2 ? i + 1 : i
    }
    function end() {
        if (!dragging) return
        const f = from, s = slot
        from = -1; slot = -1
        // The gap just before or after itself: it stays
        if (s < 0 || s === f || s === f + 1) return
        const id = app.shown[f].id
        const args = s < app.shown.length ? ["--before", app.shown[s].id, "--", id] : ["--to", "bottom", "--", id]
        place(f, s > f ? s - 1 : s)
        send(args)
    }

    // Near the view's top or bottom edge, the rows scroll under the dragged one
    readonly property int edge: 36
    Timer {
        interval: 16; repeat: true
        running: root.dragging && (root.pointerY < root.edge || root.pointerY > root.view.height - root.edge)
        onTriggered: {
            const v = root.view
            const speed = root.pointerY < root.edge ? -(root.edge - root.pointerY) : root.pointerY - (v.height - root.edge)
            const top = v.originY - v.topMargin
            const end = Math.max(top, v.originY + v.contentHeight + v.bottomMargin - v.height)
            v.contentY = Math.max(top, Math.min(end, v.contentY + speed / 3))
            root.aim()
        }
    }

    // The line where it would go: between two rows, over the list's spacing
    Rectangle {
        visible: root.dragging && root.slot >= 0 && root.slot !== root.from && root.slot !== root.from + 1
        readonly property var below: root.view.itemAtIndex(Math.min(root.slot, root.app.shown.length - 1))
        x: 12; width: root.view.width - 24
        height: 2; radius: 1
        y: !below ? 0 : root.slot < root.app.shown.length ? below.y - 2 : below.y + below.height
        color: root.c.accent
    }
}
