import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.kit

// The picked recording's transcript, under its player in RecordingView: NAME.txt as lib/transcribe.py writes it, a
// paragraph for each minute or so, "[mm:ss] text". A paragraph's time is a link: a click plays the recording from
// there, and the paragraph being played stands out. Without a transcript, Transcribe (t); while one is made, how far
// it is and Cancel (t again); one that failed, why, and Try again. The model and its language are Settings' (⌘,):
// a model not installed says what to install instead.
Item {
    id: tv
    required property QtObject c
    required property var store
    required property var player
    property bool compact: false
    readonly property var rec: store.current
    readonly property var job: rec ? store.job(rec.name) : null
    readonly property bool working: !!job && job.state !== "failed"
    readonly property bool hasText: !!rec && !!rec.transcript
    signal openSettings()                    // the model's button: Settings, where it is picked

    // [{ at: seconds (-1 without a time), stamp: "01:02", text }]
    property var paragraphs: []
    function parse(text) {
        paragraphs = (text || "").split(/\n\s*\n/).map(p => p.trim()).filter(p => p).map(p => {
            const m = p.match(/^\[(\d+):(\d\d)\]\s*([\s\S]*)$/)
            return m ? { at: +m[1] * 60 + +m[2], stamp: m[1] + ":" + m[2], text: m[3] } : { at: -1, stamp: "", text: p }
        })
    }
    // The paragraph the player is in: the last one that begins before its place
    readonly property int playing: {
        if (!player.playing && player.position <= 0) return -1
        let at = -1
        for (let i = 0; i < paragraphs.length; i++) if (paragraphs[i].at >= 0 && paragraphs[i].at <= player.position) at = i
        return at
    }
    function playFrom(seconds) { player.seek(seconds); if (!player.playing) player.play() }
    // t: Transcribe, or stop the one under way
    function toggle() {
        if (!rec) return
        if (working) store.cancelTranscript(rec.name)
        else store.transcribe(rec.name)
    }

    FileView {
        id: file
        path: tv.hasText ? tv.rec.transcript : ""
        onLoaded: tv.parse(text())
        onLoadFailed: tv.parse("")
        onPathChanged: if (!path) tv.parse("")
    }
    // A transcript written anew (Transcribe again) keeps its path: read it whenever the list is read
    Connections { target: tv.store; function onRecordingsChanged() { if (file.path) file.reload() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            z: 2                                     // its button's tip over the text below
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: "Transcript"
                font.family: tv.c.font; font.pixelSize: 13; font.weight: Font.DemiBold
                color: tv.c.text
            }
            // The model in use, in sight: a click opens Settings to pick the other one
            AppBarButton {
                c: tv.c
                glyph: "settings"
                label: (tv.store.models[tv.store.config.model] || {}).label || ""
                compact: tv.compact
                tip: "The model: Settings"
                keys: "⌘,"
                onClicked: tv.openSettings()
            }
            Item { Layout.fillWidth: true }
            AppBarButton {
                visible: !!tv.rec && (tv.working || tv.hasText || (!!tv.job && tv.job.state === "failed"))
                c: tv.c
                glyph: tv.working ? "x" : "refresh-cw"
                label: tv.working ? "Cancel" : tv.job ? "Try again" : "Transcribe again"
                compact: tv.compact
                tip: tv.working ? "Stop transcribing (the transcript before it stays)" : "Transcribe it again"
                keys: "t"
                tipAlign: "right"
                onClicked: tv.toggle()
            }
        }

        // How far it is: a thin bar and the pieces done
        ColumnLayout {
            visible: tv.working
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4; radius: 2
                color: tv.c.divider
                Rectangle {
                    height: parent.height; radius: 2
                    width: tv.job && tv.job.total ? parent.width * tv.job.done / tv.job.total : 0
                    color: tv.c.accent
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: !tv.job ? "" : tv.job.state === "queued" ? "Waiting for the transcription before it…"
                    : tv.job.total ? "Transcribing… " + tv.job.done + " of " + tv.job.total + " minutes"
                    : "Transcribing…"
                font.family: tv.c.font; font.pixelSize: 12
                color: tv.c.dim
            }
        }

        Text {
            visible: !!tv.job && tv.job.state === "failed"
            Layout.fillWidth: true
            wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: tv.job && tv.job.error ? tv.job.error : ""
            font.family: tv.c.font; font.pixelSize: 12
            color: tv.c.danger
        }

        // Not transcribed yet
        ColumnLayout {
            visible: !!tv.rec && !tv.hasText && !tv.job
            z: 1
            Layout.fillWidth: true
            spacing: 8
            AppButton {
                c: tv.c
                glyph: "captions"
                label: "Transcribe"
                keys: "t"
                tip: (tv.store.models[tv.store.config.model] || {}).about || ""
                enabled: !tv.store.modelMissing
                onClicked: tv.toggle()
            }
            // What to install: selectable, so the command can be copied
            TextEdit {
                visible: tv.store.modelMissing !== ""
                Layout.fillWidth: true
                readOnly: true; selectByMouse: true
                wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
                text: tv.store.modelMissing
                font.family: tv.c.font; font.pixelSize: 11
                color: tv.c.faint
                selectionColor: tv.c.accent
            }
        }

        Flickable {
            id: flick
            visible: tv.hasText
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: paras.implicitHeight + 12
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: paras
                width: flick.width
                spacing: 12
                Text {
                    visible: tv.paragraphs.length === 0
                    text: "Nothing could be made out."
                    font.family: tv.c.font; font.pixelSize: 12
                    color: tv.c.faint
                }
                Repeater {
                    model: tv.paragraphs
                    Row {
                        required property var modelData
                        required property int index
                        width: paras.width
                        spacing: 10
                        Text {
                            id: stamp
                            width: 40
                            text: modelData.stamp
                            font.family: tv.c.font; font.pixelSize: 12
                            font.features: { "tnum": 1 }
                            font.underline: stampHover.hovered
                            color: tv.c.accent
                            HoverHandler { id: stampHover; cursorShape: Qt.PointingHandCursor; enabled: modelData.at >= 0 }
                            TapHandler { enabled: modelData.at >= 0; onTapped: tv.playFrom(modelData.at) }
                        }
                        TextEdit {
                            width: parent.width - stamp.width - parent.spacing
                            readOnly: true; selectByMouse: true
                            wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
                            text: modelData.text
                            font.family: tv.c.font; font.pixelSize: 13
                            color: index === tv.playing ? tv.c.title : tv.c.text
                            selectionColor: tv.c.accent
                        }
                    }
                }
            }
        }
        Item { visible: !tv.hasText; Layout.fillHeight: true }
    }
}
