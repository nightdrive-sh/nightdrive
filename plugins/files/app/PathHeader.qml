import QtQuick
import QtQuick.Layouts
import qs
import qs.kit
import "Format.js" as Format

// Over the list: back and forward, where the window is, as a path whose parts are clicked to go up to them (home is ~), level with the
// sidebar's title, and the buttons: Filter, New folder, the preview; in the trash, Put back and Empty. With the filter
// open (/ or ⌘F) the field takes the path's place: typing narrows the list at once, ⏎ or ↓ go back to the rows with
// it kept, Esc ends it. In a narrow window the buttons give up their words, and the path its first parts.
RowLayout {
    id: root
    required property QtObject c
    required property var app
    readonly property alias field: search
    readonly property bool compact: width < 560
    spacing: 4

    // The path's parts from the left: [{ name, path }], home's own as "~"
    readonly property var crumbs: {
        const p = app.path, home = app.home
        const out = []
        let rest = p, start = "/"
        if (p === home || p.startsWith(home + "/")) { out.push({ name: "~", path: home }); rest = p.slice(home.length); start = home }
        else out.push({ name: "/", path: "/" })
        let at = start
        for (const part of rest.split("/").filter(x => x)) { at = Format.join(at, part); out.push({ name: part, path: at }) }
        return out
    }

    // Back and forward for the mouse, as in Nautilus and at its size (34 px to click, past the header's 30): dimmed,
    // and deaf, with nowhere to go. The keys have ⌥← ⌥→
    Repeater {
        model: [{ glyph: "arrow-left", tip: "Back", keys: "⌥←", can: root.app.history.length > 0, go: () => root.app.back() },
                { glyph: "arrow-right", tip: "Forward", keys: "⌥→", can: root.app.future.length > 0, go: () => root.app.forward() }]
        // An item of the header's height holds each, so the bigger button doesn't make the row taller
        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            implicitWidth: 34; implicitHeight: 30
            Layout.rightMargin: index === 1 ? 10 : 0
            AppIconButton {
                anchors.centerIn: parent
                implicitWidth: 34; implicitHeight: 34; radius: 8
                c: root.c; glyph: slot.modelData.glyph; glyphSize: 20; tip: slot.modelData.tip; keys: slot.modelData.keys
                enabled: slot.modelData.can
                opacity: enabled ? 1 : 0.35
                onClicked: slot.modelData.go()
            }
        }
    }
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        visible: !root.app.filtering
        Text {
            visible: root.app.trashShown
            anchors.verticalCenter: parent.verticalCenter
            text: "Trash"
            color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        // The last parts stay in sight: a long path lets its first ones go off the left
        Row {
            id: crumbRow
            visible: !root.app.trashShown
            anchors.verticalCenter: parent.verticalCenter
            x: Math.min(0, parent.width - width)
            spacing: 2
            Repeater {
                model: root.crumbs
                delegate: Row {
                    required property var modelData
                    required property int index
                    readonly property bool last: index === root.crumbs.length - 1
                    spacing: 2
                    Text {
                        visible: index > 1 || (index === 1 && root.crumbs[0].name !== "/")
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 13
                        leftPadding: 8; rightPadding: 8
                    }
                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: last ? root.c.title : crumbHover.hovered ? root.c.text : root.c.dim
                        font.family: root.c.font; font.pixelSize: 13; font.weight: last ? Font.Medium : Font.Normal
                        HoverHandler { id: crumbHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.app.go(modelData.path, "") }
                    }
                }
            }
        }
    }
    AppSearchField {
        id: search
        visible: root.app.filtering
        Layout.fillWidth: true
        c: root.c
        placeholder: "Filter by name"
        onEdited: root.app.filter = text
        onReturnPressed: root.app.toList()
        onDownPressed: root.app.toList()
        onEscapePressed: root.app.endFilter()
    }

    // How many are marked, while some are (the folder's own count isn't shown: Jari's call)
    Text {
        visible: root.app.marked.length > 0
        text: root.app.marked.length + " marked"
        color: root.c.accent; font.family: root.c.font; font.pixelSize: 11
        Layout.rightMargin: 8
    }
    AppBarButton {
        visible: root.app.trashShown && root.app.rows.length > 0
        c: root.c; glyph: "undo-2"; label: root.compact ? "" : "Put back"; compact: root.compact; tip: "Put back where it was"; keys: "u"
        onClicked: root.app.acts.restorePicked()
    }
    AppBarButton {
        visible: root.app.trashShown && root.app.rows.length > 0
        c: root.c; glyph: "trash"; label: root.compact ? "" : "Empty"; compact: root.compact; tip: "Empty the trash"; keys: "⌘⇧⌫"; tipAlign: "right"
        onClicked: root.app.acts.askEmpty()
    }
    AppBarButton {
        visible: !root.app.trashShown
        c: root.c; glyph: "search"; glyphSize: 17; compact: true; tip: "Filter by name"; keys: "/"
        onClicked: root.app.startFilter()
    }
    AppBarButton {
        visible: !root.app.trashShown
        c: root.c; glyph: "folder-plus"; glyphSize: 17; compact: true; tip: "New folder"; keys: "⌘⇧N"
        onClicked: root.app.acts.askNew(true)
    }
    AppBarButton {
        c: root.c; glyph: root.app.previewShown ? "panel-right-close" : "panel-right-open"; glyphSize: 17; compact: true
        tip: root.app.previewShown ? "Hide the preview" : "Show the preview"; keys: "i"; tipAlign: "right"
        onClicked: root.app.previewChoice = !root.app.previewShown
    }
}
