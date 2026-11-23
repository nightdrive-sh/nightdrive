import QtQuick
import QtQuick.Layouts
import qs
import qs.kit
import "Format.js" as Format

// Over the list: back and forward, where the window is, as a path whose parts are clicked to go up to them (home is
// its glyph) and take files dropped on them, level with the sidebar's title, and the buttons: Filter, New folder, the grid or the list, the preview;
// in the trash, Put back and Empty. With the filter open (/ or ⌘F) the field takes the path's place: typing narrows
// the list at once, ⏎ or ↓ go back to the rows with it kept, Esc ends it; its scope at its end turns it into a search of
// all of home (Search). In a narrow window the buttons give up their
// words, and the path its first parts.
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
            Layout.rightMargin: index === 1 ? 15 : 0
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
                    // The archive looked into (Archive): its glyph before its name, so the parts after it read as
                    // inside it
                    Text {
                        visible: modelData.path === root.app.archive.file
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.g("package-open")
                        font.family: Icons.family; font.pixelSize: 14
                        color: root.c.accent
                        rightPadding: 4; topPadding: 2
                    }
                    // Home is its glyph, as in the sidebar, rather than ~
                    Text {
                        readonly property bool home: modelData.name === "~"
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: home ? Icons.g("house") : modelData.name
                        color: last ? root.c.title : crumbHover.hovered ? root.c.text : root.c.dim
                        font.family: home ? Icons.family : root.c.font; font.pixelSize: home ? 14 : 13
                        font.weight: last ? Font.Medium : Font.Normal
                        topPadding: home ? 2 : 0         // centred, the glyph sat 1 px above the names' line
                        HoverHandler { id: crumbHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.app.go(modelData.path, "") }
                        // Files dropped on a part of the path go into that folder, as onto a folder's row: moved from
                        // Files, copied from another app. A frame shows where they would land
                        Rectangle {
                            z: -1
                            anchors.fill: parent; anchors.margins: -5; anchors.leftMargin: -7; anchors.rightMargin: -7
                            radius: 6
                            visible: crumbDrop.containsDrag
                            color: root.c.hover
                            border.color: root.c.primary
                        }
                        DropArea {
                            id: crumbDrop
                            anchors.fill: parent; anchors.margins: -6
                            keys: ["text/uri-list"]
                            onDropped: e => root.app.acts.dropped(e, modelData.path, false)
                        }
                    }
                }
            }
        }
    }
    AppSearchField {
        id: search
        visible: root.app.filtering
        Layout.fillWidth: true
        Layout.minimumWidth: 90         // the scope beside it gives way first
        c: root.c
        placeholder: root.app.below ? "Search by name" : "Filter by name"
        onEdited: root.app.filter = text
        onReturnPressed: root.app.toList()
        onDownPressed: root.app.toList()
        onEscapePressed: root.app.endFilter()
    }

    // How many a search found, once it is done, before the scope; none when it stopped at its limit (Jari: no "first 2000")
    Text {
        visible: !root.compact && root.app.searching && !root.app.search.running && !root.app.search.capped
                 && root.app.marked.length === 0 && root.app.rows.length > 0
        text: root.app.rows.length + " found"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
        Layout.rightMargin: 8
    }
    // The filter's scope, at the field's end: a click (or Tab, ⌘F again) turns it between this folder and all of home
    // (outside home: the folder and the ones below it). Not a second search button: the one field does both, as the
    // Mac's ⌘F does with the folder and "This Mac"
    Rectangle {
        id: scope
        visible: root.app.filtering
        Layout.maximumWidth: Math.max(70, root.width * 0.4)
        Layout.preferredWidth: Math.min(scopeText.implicitWidth + 20, Layout.maximumWidth)
        Layout.preferredHeight: 22
        Layout.rightMargin: 8
        radius: 6
        color: root.app.below ? root.c.sel : scopeHover.hovered ? root.c.hover : "transparent"
        border.color: root.app.below ? root.c.primary : root.c.divider
        readonly property string place: Format.base(root.app.path)
        Text {
            id: scopeText
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            text: !root.app.below ? (root.app.path === root.app.home ? "This folder" : scope.place)
                : root.app.inHome ? "Home" : scope.place + " and below"
            color: root.app.below ? root.c.primary : scopeHover.hovered ? root.c.text : root.c.dim
            font.family: root.c.font; font.pixelSize: 11
        }
        HoverHandler { id: scopeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.app.toggleScope() }
        // Under the box, its right edge with the box's, as the header's buttons have theirs
        Tip {
            x: parent.width - width; y: parent.height + 6
            c: root.c; hovered: scopeHover.hovered; keys: "Tab"
            text: root.app.below ? "Only this folder"
                : root.app.inHome ? "All of home, every folder in it" : "This folder and every folder below it"
        }
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
    // Inside an archive: nothing in it changes (Archive)
    Text {
        visible: root.app.inArchive && !root.compact
        text: "Read-only"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
        Layout.rightMargin: 8
    }
    AppBarButton {
        visible: !root.app.trashShown && !root.app.inArchive
        c: root.c; glyph: "folder-plus"; glyphSize: 17; compact: true; tip: "New folder"; keys: "⌘⇧N"
        onClicked: root.app.acts.askNew(true)
    }
    // The grid or the list (t): it shows the one it turns to
    AppBarButton {
        visible: !root.app.trashShown && !root.app.inArchive
        c: root.c; glyph: root.app.gridShown ? "list" : "layout-grid"; glyphSize: 17; compact: true
        tip: root.app.gridShown ? "As a list" : "As a grid, with thumbnails"; keys: "t"
        onClicked: root.app.toggleView()
    }
    AppBarButton {
        c: root.c; glyph: root.app.previewShown ? "panel-right-close" : "panel-right-open"; glyphSize: 17; compact: true
        tip: root.app.previewShown ? "Hide the preview" : "Show the preview"; keys: "i"; tipAlign: "right"
        onClicked: root.app.previewChoice = !root.app.previewShown
    }
}
