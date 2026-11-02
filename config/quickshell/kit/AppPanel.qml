import QtQuick
import qs

// A panel over the window (settings, a question before what can't be undone, a first start): the window dimmed behind a
// card in the middle, what it holds in a column inside. A click outside comes out as outsideTapped (most panels close on
// it); its keys are the app's (Keys.onPressed on the panel, once it has the focus). behind is the window's content under
// it, turned off while the panel shows: in Qt 6 the pointer handlers under an item that takes a press still get it, so a
// click on the panel also clicked the row under it (#1683). The focus goes back where it was if the app gives it nowhere.
//
// The card never grows past the window (#2027): in a short window its column scrolls inside it, as a top bar menu taller
// than the screen does (#1753), and the panel's answers (the last child holding an AppPanelButton: Save and Cancel) are
// lifted out of the column into a footer under it, so they stay in sight however far the rest scrolls. That is done
// here, from what the panels already declare, so no app has to change. In a narrow window the card takes the window's
// width less a margin, and its padding shrinks with a short or narrow window so the content keeps the room.
Rectangle {
    id: root
    required property QtObject c
    property int cardWidth: 560
    property alias spacing: column.spacing
    default property alias content: column.data
    property Item behind: null
    signal outsideTapped()
    anchors.fill: parent
    color: c.scrim
    Binding { target: root.behind; property: "enabled"; value: false; when: root.visible && root.behind !== null }
    property Item focusBefore: null
    onVisibleChanged: {
        if (visible) {
            focusBefore = Window.activeFocusItem
            flick.contentY = 0          // a panel opens at its top
            return
        }
        // After the app's own focus call, which may have come while behind was still off
        const back = focusBefore
        Qt.callLater(() => { if (back && !Window.activeFocusItem) back.forceActiveFocus() })
    }

    // The card's padding: the old 40 / 36 where there is room, less in a narrow or short window
    readonly property int padX: width < 480 ? 20 : 40
    readonly property int padY: height < 480 ? 18 : 36
    readonly property int margin: 12    // between the card and the window's edges

    // The answers: the last child of the column that is or holds an AppPanelButton (a Row of them, Garage's Item with
    // Delete beside them). Looked for once the panel is built; moved into the footer, where `parent.width` and
    // `anchors.right: parent.right` mean the same as they did in the column.
    function holdsAnswer(it, depth) {
        if (!it) return false
        if (it.panelAnswer === true) return true
        if (depth <= 0) return false
        for (let i = 0; i < it.children.length; i++)
            if (holdsAnswer(it.children[i], depth - 1)) return true
        return false
    }
    Component.onCompleted: {
        const kids = column.children
        for (let i = kids.length - 1; i >= 0; i--) {
            if (!holdsAnswer(kids[i], 3)) continue
            const it = kids[i]
            it.parent = footer
            it.y = 0                        // the column had placed it at its own height (x it leaves alone, as Column does)
            return
        }
    }

    // A focused field out of sight (Tab, the app's focus call) scrolls into it
    function showFocus() {
        const it = Window.activeFocusItem
        if (!visible || !it || !flick.interactive) return
        let q = it
        while (q && q !== column) q = q.parent
        if (!q) return                      // not in the column (the footer, another window part): nothing to scroll
        const y = it.mapToItem(column, 0, 0).y
        const pad = 8
        if (y - pad < flick.contentY) flick.contentY = Math.max(0, y - pad)
        else if (y + it.height + pad > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, y + it.height + pad - flick.height)
    }
    Connections { target: root.Window.window; function onActiveFocusItemChanged() { Qt.callLater(root.showFocus) } }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.outsideTapped()
        onWheel: wheel => wheel.accepted = true
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.cardWidth, root.width - 2 * root.margin)
        readonly property real footerRoom: footer.height > 0 ? footer.height + column.spacing : 0
        readonly property real fullHeight: column.implicitHeight + footerRoom + 2 * root.padY
        height: Math.min(fullHeight, root.height - 2 * root.margin)
        radius: 14
        color: root.c.solid
        border.color: root.c.line
        MouseArea { anchors.fill: parent }      // a click inside keeps it open

        // Interactive only when the column doesn't fit, so a drag or a wheel otherwise stays the content's own
        Flickable {
            id: flick
            x: root.padX; y: root.padY
            width: card.width - 2 * root.padX
            height: card.height - 2 * root.padY - card.footerRoom
            contentWidth: width
            contentHeight: column.implicitHeight
            interactive: contentHeight > height + 0.5
            clip: interactive
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            TouchScroll { view: flick; enabled: flick.interactive }
            Column {
                id: column
                width: flick.width
                spacing: 18
            }
        }
        // There is more above or below: a line at the scrolled edge, as the card's own border
        Rectangle {
            visible: flick.interactive && flick.contentY > 1
            x: 0; width: card.width; height: 1; y: flick.y - 1
            color: root.c.line
        }
        Rectangle {
            visible: flick.interactive && flick.contentY < flick.contentHeight - flick.height - 1
            x: 0; width: card.width; height: 1; y: flick.y + flick.height
            color: root.c.line
        }
        // Where the column is in its whole: a thin bar by the right edge, only while it scrolls
        Rectangle {
            visible: flick.interactive
            x: card.width - 6; width: 3; radius: 1.5
            y: flick.y + flick.visibleArea.yPosition * flick.height
            height: Math.max(16, flick.visibleArea.heightRatio * flick.height)
            color: root.c.line
        }
        Item {
            id: footer
            x: root.padX
            y: card.height - root.padY - height
            width: card.width - 2 * root.padX
            height: children.length > 0 && children[0].visible ? children[0].height : 0
        }
    }
}
