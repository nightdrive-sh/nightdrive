import QtQuick

// The picture: the desk's screens as tiles in proportion, fitted to the window however wide or narrow, and below them
// the shelf of virtual screens put away (AwayShelf). A tile dragged follows the pointer; dropped on the desk, its place
// goes to arrange (Screens.move), which snaps it beside the nearest screen and answers with the new arrangement; dropped
// on the shelf, a virtual screen goes away, and one dragged off the shelf comes back to the desk where it is dropped.
Item {
    id: root
    required property QtObject c
    required property Screens model
    property string selected: ""
    signal picked(string id)
    signal refused(string text)

    readonly property int pad: 24
    readonly property bool hasVirtual: model.screens.some(s => s.kind === "virtual")
    // 11 px above its title and below its tiles; the tiles as tall as before
    readonly property int shelfH: hasVirtual ? Math.min(116, Math.max(82, height * 0.2 + 6)) : 0
    readonly property real deskH: height - shelfH - (hasVirtual ? 12 : 0)

    // The desk's bounds in layout px, and the scale that fits them in with room around to drag a screen to any side
    readonly property var bounds: {
        const d = model.desk
        if (!d.length) return { x0: 0, y0: 0, w: 1, h: 1 }
        const x0 = Math.min(...d.map(s => s.x)), y0 = Math.min(...d.map(s => s.y))
        return { x0: x0, y0: y0, w: Math.max(...d.map(s => s.x + s.w)) - x0, h: Math.max(...d.map(s => s.y + s.h)) - y0 }
    }
    readonly property real fit: Math.max(0.005, Math.min((width - 2 * pad) / bounds.w, (deskH - 2 * pad) / bounds.h) * 0.8)
    readonly property real ox: (width - bounds.w * fit) / 2
    readonly property real oy: (deskH - bounds.h * fit) / 2

    // The shelf's tiles: as tall as it lets them be, side by side after its label
    readonly property real shelfTileH: shelfH - 40
    // wide enough for its name, a phone's narrow shape too
    function shelfW(s) { return Math.max(96, s.w / s.h * shelfTileH) }
    // Side by side, 10 px apart, the row centred on the shelf
    function shelfX(s) {
        const total = model.away.reduce((t, a) => t + shelfW(a), 0) + 10 * Math.max(0, model.away.length - 1)
        let x = Math.max(shelf.firstX, (width - total) / 2)
        for (const a of model.away) { if (a.id === s.id) return x; x += shelfW(a) + 10 }
        return x
    }

    // The tile on the move: its top left in this item, and where the pointer took hold of it (as a share of its size)
    property string dragId: ""
    property real dragX: 0
    property real dragY: 0
    property real holdX: 0
    property real holdY: 0
    property bool moved: false
    property real pointerY: 0
    readonly property bool overShelf: hasVirtual && dragId !== "" && moved && pointerY > deskH

    // A new arrangement (or the same one again) puts the dropped tile where arrange says
    Connections { target: root.model; function onScreensChanged() { if (!root.moved) root.dragId = "" } }

    AwayShelf {
        id: shelf
        visible: root.hasVirtual
        c: root.c
        y: root.height - root.shelfH; width: root.width; height: root.shelfH
        empty: root.model.away.length === 0
        lit: root.overShelf
    }

    Repeater {
        model: root.model.screens
        ScreenTile {
            id: tile
            required property var modelData
            c: root.c
            screen: modelData
            selected: root.selected === modelData.id
            lifted: root.dragId === modelData.id && root.moved
            readonly property bool held: root.dragId === modelData.id
            readonly property bool shelved: modelData.away && !held
            // On the desk's scale while it moves, so it shows where it would go
            // A hair's gap between neighbours, so two that touch still read as two
            width: shelved ? root.shelfW(modelData) : modelData.w * root.fit - 3
            height: shelved ? root.shelfTileH : modelData.h * root.fit - 3
            x: held ? root.dragX : shelved ? root.shelfX(modelData) : root.ox + (modelData.x - root.bounds.x0) * root.fit
            y: held ? root.dragY : shelved ? shelf.y + 29 : root.oy + (modelData.y - root.bounds.y0) * root.fit
            Behavior on x { enabled: !tile.held; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !tile.held; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            onPicked: root.picked(modelData.id)
            onGrabbed: (px, py) => {
                root.holdX = px / width; root.holdY = py / height
                root.dragX = x; root.dragY = y
                root.moved = false
                root.dragId = modelData.id
            }
            onDragged: (px, py) => {
                const p = mapToItem(root, px, py)
                // A few pixels' wobble of a click is no move
                if (!root.moved && Math.abs(p.x - (x + root.holdX * width)) + Math.abs(p.y - (y + root.holdY * height)) < 4) return
                root.moved = true
                root.pointerY = p.y
                const w = modelData.w * root.fit, h = modelData.h * root.fit
                root.dragX = p.x - root.holdX * w
                root.dragY = p.y - root.holdY * h
            }
            onDropped: root.drop(modelData)
        }
    }

    function drop(s) {
        if (!moved) { dragId = ""; return }
        const shelved = overShelf          // read before moved goes false: overShelf counts only a tile on the move
        moved = false
        if (shelved) {
            if (s.kind !== "virtual") { dragId = ""; refused("Only a virtual screen goes on the shelf: the desk's are where they are"); return }
            if (s.away) { dragId = ""; return }
            model.putAway(s.id)
            return
        }
        model.move(s.id, bounds.x0 + (dragX - ox) / fit, bounds.y0 + (dragY - oy) / fit)
    }
}
