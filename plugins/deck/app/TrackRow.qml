import QtQuick
import qs
import qs.kit

// A row of the view's list (ViewList's delegate): an artist, an album, a genre, a song or a track, with its cover or
// number, its marks (the shelf's icon, a favourite's star) and what is on the right. Its own file because every view
// draws its rows with it, and how a cover sits beside a long Curated reason is fiddly enough to keep in one place.
AppRow {
    id: r
    required property var modelData
    required property int index
    readonly property var list: ListView.view
    readonly property var win: list.win
    readonly property bool current: index === list.currentIndex
    // The playing track, or the album it plays from
    readonly property bool now: win.player.info !== null && (
        modelData.kind === "nowplaying" ||
        (modelData.kind === "track" || modelData.kind === "song" || modelData.kind === "radiotrack") && modelData.data.uri === win.player.info.track_uri
        || modelData.kind === "album" && modelData.data.uri === win.player.info.album_uri
        || modelData.kind === "genre" && win.player.radio !== null && win.player.radio.genre === modelData.data.id)
    // An album on your shelf has the shelf's icon (Deck's green ●); a favourite genre has a star
    readonly property bool dotted: modelData.kind === "album" && win.nav.view.kind !== "shelf" && !!win.lib.shelfUris[modelData.data.uri]
    // A cover beside a reason (Curated) is as tall as the texts; beside a line or two, a small one
    readonly property bool tall: !!modelData.cover && !!modelData.note
    implicitHeight: Math.max(body.implicitHeight, art.visible ? art.height : 0) + 20
    c: win.look
    selected: current && list.activeFocus && !win.nav.sectionsKeyed
    marked: current
    active: true        // selected only while the keys are here: the kit's frame
    TapHandler {
        // An artist, an album or a genre opens with one click (only browsing: Esc comes back); a song plays
        // with two, so picking one doesn't stop the music
        onTapped: {
            r.win.nav.moveTo(r.index); r.list.forceActiveFocus()
            if (["artist", "album", "genre"].indexOf(r.modelData.kind) >= 0) r.win.act.activate(r.modelData)
        }
        onDoubleTapped: if (["artist", "album", "genre"].indexOf(r.modelData.kind) < 0) r.win.act.activate(r.modelData)
    }
    Text {
        id: lead
        x: 14; width: r.list.leadWidth
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        visible: (r.modelData.number !== undefined || r.now) && r.modelData.cover === undefined
        text: r.now ? Icons.g("music") : r.modelData.number || ""
        font.family: r.now ? Icons.family : c.font; font.pixelSize: r.now ? 13 : 11
        color: r.now ? c.primary : c.faint
    }
    // An album's cover (Curated's as tall as the texts beside it with a two-line reason, its top at
    // theirs: a selected row's longer reason runs on below it)
    // (From the fonts, not the texts' heights: those hang on the width, which hangs on the cover)
    FontMetrics { id: titleMetrics; font: titleText.font }
    FontMetrics { id: subMetrics; font: subText.font }
    FontMetrics { id: noteMetrics; font: noteText.font }
    Image {
        id: art
        visible: r.modelData.cover !== undefined
        x: 12
        anchors.top: r.tall ? body.top : undefined
        anchors.verticalCenter: r.tall ? undefined : parent.verticalCenter
        height: r.tall ? Math.ceil(titleMetrics.height) + Math.ceil(subMetrics.height) + subText.bottomPadding + 2 * Math.ceil(noteMetrics.height * noteText.lineHeight) + 2 * body.spacing
                       : 36
        width: height
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectCrop
        source: r.modelData.cover ? r.win.covers.cover(r.modelData.cover) : ""
        Rectangle { anchors.fill: parent; color: c.hover; visible: parent.status !== Image.Ready }
    }
    Column {
        id: body
        anchors.left: art.visible ? art.right : lead.visible ? lead.right : parent.left
        anchors.leftMargin: art.visible ? (r.tall ? 17 : 14) : lead.visible ? 14 : 16
        anchors.right: right.left; anchors.rightMargin: 16
        // Beside a tall cover from the top, so a one-line reason doesn't leave the cover hanging below
        anchors.top: r.tall ? parent.top : undefined
        anchors.topMargin: 10
        anchors.verticalCenter: r.tall ? undefined : parent.verticalCenter
        spacing: 3
        Row {
            width: parent.width
            spacing: 8
            Text {
                id: titleText
                width: Math.min(implicitWidth, parent.width - (dot.visible ? dot.implicitWidth + 8 : 0) - (star.visible ? star.implicitWidth + 8 : 0) - (byText.visible ? Math.min(byText.implicitWidth, parent.width / 3) : 0))
                elide: Text.ElideRight
                text: r.modelData.title; textFormat: Text.PlainText
                font.family: c.font; font.pixelSize: 13
                color: r.now ? c.accent : c.title
            }
            // A track's own artists, when not the album's: after its name, as quiet as a second line
            Text {
                id: byText
                visible: !!r.modelData.by
                anchors.baseline: titleText.baseline
                width: Math.min(implicitWidth, parent.width - titleText.width - parent.spacing)
                elide: Text.ElideRight
                text: "– " + (r.modelData.by || ""); textFormat: Text.PlainText
                font.family: c.font; font.pixelSize: 12; color: c.dim
            }
            // On your shelf: the shelf's icon, as the player's button by the playing album
            Text {
                id: dot
                visible: r.dotted
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g("library"); font.family: Icons.family; font.pixelSize: 12
                color: c.primary
            }
            Text {
                id: star
                visible: !!r.modelData.fav
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g("star"); font.family: Icons.family; font.pixelSize: 12
                color: c.primary
            }
        }
        // The second line, and a Curated album's rough genre after it, fainter ("· jazz", "· rock, psych"),
        // so the list can be skimmed by genre
        Row {
            width: parent.width
            visible: !!r.modelData.sub
            Text {
                id: subText
                bottomPadding: r.modelData.note ? 5 : 0     // a little air before the reason
                width: Math.min(implicitWidth, parent.width - (genreText.visible ? genreText.implicitWidth : 0))
                elide: Text.ElideRight
                text: r.modelData.sub || ""; textFormat: Text.PlainText
                font.family: c.font; font.pixelSize: 12; color: c.dim
            }
            Text {
                id: genreText
                visible: !!r.modelData.genre
                anchors.baseline: subText.baseline
                text: " · " + (r.modelData.genre || ""); textFormat: Text.PlainText
                font.family: c.font; font.pixelSize: 11; color: c.faint
            }
        }
        Text {
            id: noteText
            visible: !!r.modelData.note
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: r.current ? 6 : 2
            elide: Text.ElideRight
            text: r.modelData.note || ""; textFormat: Text.PlainText
            font.family: c.font; font.pixelSize: 11; color: c.faint; lineHeight: 1.2
        }
    }
    // On the right: a duration or a year, or for the queue's playing track the note the album's
    // list shows on the left
    Text {
        id: right
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool note: r.modelData.kind === "nowplaying"
        text: note ? Icons.g("music") : r.modelData.right || ""; textFormat: Text.PlainText
        font.family: note ? Icons.family : c.font; font.pixelSize: note ? 13 : 11
        // A Curated album you have listened to, in the theme's colour
        color: note || r.modelData.right === "Listened" ? c.primary : c.faint
    }
}
