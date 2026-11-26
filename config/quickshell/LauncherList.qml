import QtQuick
import Quickshell

// The launcher's list of rows (LauncherRow.qml) and how tall it is: as tall as its rows, up to maxRows or the room the
// screen leaves. A row's height depends on its kind and on how many lines its description wraps to, so the list measures
// those here, with the same fonts the rows draw with.
ListView {
    id: list
    required property var launcher

    readonly property int headerHeight: 40
    // A row's description (sub) wraps, up to subMaxLines (or the row's own subMax: a snippet's lines): each line after
    // the first makes the row this much taller. subPlain: in the name's font instead (a snippet's text, all of it alike)
    readonly property int subMaxLines: 3
    readonly property int subLineHeight: Math.ceil(subMetrics.height)
    readonly property int plainLineHeight: Math.ceil(plainMetrics.height)
    FontMetrics { id: subMetrics; font { family: Theme.font; pixelSize: list.launcher.fontSize - 5; weight: list.launcher.fontWeight } }
    FontMetrics { id: plainMetrics; font { family: Theme.font; pixelSize: list.launcher.fontSize; weight: list.launcher.fontWeight } }
    // A quote's lines (its name, already cut to a few lines) and the box's padding
    readonly property int quoteLineHeight: Math.ceil(quoteMetrics.height)
    readonly property int quotePad: 12
    FontMetrics { id: quoteMetrics; font { family: Theme.font; pixelSize: list.launcher.fontSize - 3; weight: list.launcher.fontWeight } }
    function quoteHeight(it) { return it.name.split("\n").length * quoteLineHeight + 2 * quotePad }
    // The lines a row's description takes (an estimate from its width, for the list's height; the row measures its own)
    function subLines(it) {
        if (!it.sub || launcher.fixedRow(it)) return 1
        const room = Math.max(1, list.width - launcher.iconSize - 70)
        const m = it.subPlain ? plainMetrics : subMetrics
        const lines = launcher.keySpaced(it.sub).split("\n").reduce((n, l) => n + Math.max(1, Math.ceil(m.advanceWidth(l) / room)), 0)
        return Math.min(it.subMax || subMaxLines, lines)
    }
    function listHeight() {
        const L = launcher
        const cap = Math.min(L.maxRows * (L.rowHeight + L.rowGap), L.listRoom)
        let h = 0
        for (const it of L.results) {
            h += (it.kind === "quote" ? quoteHeight(it) : L.fixedRow(it) ? headerHeight : L.rowHeight + (subLines(it) - 1) * (it.subPlain ? plainLineHeight : subLineHeight)) + L.rowGap
            if (h >= cap) return cap
        }
        return h
    }

    // On the grid level the list is hidden, but its currentIndex is still the selection (keys, Enter)
    visible: !list.launcher.grid && list.launcher.detail === null
    height: visible ? list.listHeight() : 0
    model: list.launcher.results
    onCurrentIndexChanged: list.launcher.leaveField()
    clip: true
    currentIndex: 0
    highlightMoveDuration: 0
    boundsBehavior: Flickable.StopAtBounds
    spacing: list.launcher.rowGap
    TouchScroll { view: list; step: list.launcher.rowHeight + list.launcher.rowGap }
    delegate: LauncherRow { launcher: list.launcher }
}
