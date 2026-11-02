import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The view's title bar: its title (with the way back), or the search field, and the view's own buttons (HeaderButtons).
// As high whatever it holds, with a line under it in the window, so the first row stays put. Its own file as the part of
// the view that changes most with what the view is (an album's cover and artist, a section's count).
Item {
    id: root
    required property var win
    readonly property QtObject c: win.look
    readonly property var nav: win.nav
    readonly property alias searchField: field
    // Over the list, so its buttons' tips aren't drawn under the first row
    z: 1

    ColumnLayout {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 28
            Layout.rightMargin: 28
            // As high as the tallest it holds (an album's cover, the buttons), so it centres in the bar
            Layout.preferredHeight: root.nav.onePane ? 40 : 30
            spacing: 10
            // The way back: a button the size of the album buttons, its arrow where the title starts
            // in a section's own view. In one pane a finger's size, and in a section's own view too,
            // to the sections.
            AppIconButton {
                visible: root.nav.stack.length > 1 || root.nav.onePane
                Layout.leftMargin: root.nav.onePane ? -16 : -8
                implicitWidth: root.nav.onePane ? 40 : 30; implicitHeight: root.nav.onePane ? 40 : 28; radius: root.nav.onePane ? 8 : 7
                c: root.c
                glyph: "arrow-left"; glyphSize: root.nav.onePane ? 17 : 16
                tip: root.nav.stack.length > 1 ? "Back" : "Sections"; keys: "Esc"
                onClicked: root.nav.back()
            }
            // As high as the title's row, so the field sits where the title does
            AppSearchField {
                id: field
                Layout.fillWidth: true
                visible: root.nav.view.kind === "search"
                c: root.c
                placeholder: "Search Spotify"
                onEdited: root.win.deck.searchLater()
                onReturnPressed: { root.win.deck.searchNow(); root.win.list.forceActiveFocus() }
                onDownPressed: root.win.list.forceActiveFocus()
                onEscapePressed: { if (text) { text = ""; root.win.deck.results = null } else if (root.nav.onePane) root.nav.openSections(); else root.win.list.forceActiveFocus() }
            }
            // The album's cover, a little taller than the line
            Image {
                visible: root.nav.view.kind === "album"
                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectCrop
                source: root.nav.view.kind === "album" ? root.win.covers.cover(root.nav.view.album.uri) : ""
                Rectangle { anchors.fill: parent; color: c.hover; visible: parent.status !== Image.Ready }
            }
            Text {
                visible: root.nav.view.kind !== "search"
                Layout.maximumWidth: implicitWidth
                // Narrow, the title is the last to give way
                Layout.minimumWidth: Math.min(implicitWidth, 160)
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.win.page.heading; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.DemiBold
            }
            // An album's artist: a click opens the artist's albums
            Text {
                id: albumArtist
                readonly property var view: root.nav.view
                readonly property bool linked: view.kind === "album" && (!!view.album.artist_id || root.nav.artistOnShelf(view.album))
                visible: view.kind === "album" && !!view.album.artist
                Layout.alignment: Qt.AlignBaseline
                Layout.leftMargin: 10
                // Its own width (a long name at most this much), the year after it in the same text, so
                // that in a narrow window the year gives way first and then the name. fillWidth only so it
                // can give way at all: without it a layout keeps the preferred width, and the album's
                // buttons were pushed out past the window's edge.
                Layout.preferredWidth: Math.min(Math.ceil(implicitWidth), 360)
                Layout.maximumWidth: Math.min(Math.ceil(implicitWidth), 360)   // ceil: a layout rounds down, and half a pixel short elides the year
                Layout.minimumWidth: 0
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.StyledText
                readonly property string name: visible ? view.album.artist.replace(/&/g, "&amp;").replace(/</g, "&lt;") : ""
                text: !visible ? "" : (arh.hovered && linked ? "<u>" + name + "</u>" : name)
                    + (root.win.page.year(view.album) ? "<font color=\"" + c.dim + "\"> · " + root.win.page.year(view.album) + "</font>" : "")
                color: arh.hovered && linked ? c.text : c.dim; font.family: c.font; font.pixelSize: 12
                HoverHandler { id: arh; enabled: albumArtist.linked; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: albumArtist.linked; onTapped: root.nav.openAlbumArtist() }
                Tip { y: parent.height + 8; c: root.c; text: "Open the artist"; hovered: arh.hovered }
            }
            // What it is, quieter on the same line (the album's year, how many Curated has). After an
            // album's artist, which has the year, it is empty and only keeps the buttons at the right.
            Text {
                visible: root.nav.view.kind !== "search"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignBaseline
                Layout.leftMargin: albumArtist.visible ? 0 : 10
                elide: Text.ElideRight
                text: albumArtist.visible ? "" : root.win.page.subheading; color: c.dim; font.family: c.font; font.pixelSize: 12
            }
            HeaderButtons { win: root.win }
        }
    }
}
