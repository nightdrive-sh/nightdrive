import QtQuick
import qs.kit

// Recorder's settings (⌘, or `recorder settings`): the folder recordings go to, the transcription's model (Fast:
// Parakeet, More exact: Whisper large-v3-turbo) and Whisper's language, and whether a saved recording is transcribed at
// once. Each change is saved as it is made (`recorder config KEY VALUE`, Store.setConfig), the folder on ⏎ or when the
// panel closes. A model that isn't installed says what to install (docs/dictation.md), selectable to copy.
AppPanel {
    id: p
    required property var store
    signal closed()
    visible: false
    cardWidth: Math.min(520, parent ? parent.width - 32 : 520)
    spacing: 18

    readonly property var conf: store.config
    readonly property var modelKeys: ["parakeet", "medium", "whisper"]
    readonly property var languageKeys: ["fi", "en", "auto"]
    readonly property var picked: store.models[conf.model] || {}
    readonly property bool whisper: conf.model === "whisper" || conf.model === "medium"   // they take a language

    function open() { store.readSettings(); folder.text = conf.folder || "~/Recordings"; visible = true; forceActiveFocus() }
    function saveFolder() {
        const f = folder.text.trim() || "~/Recordings"
        if (f !== conf.folder) store.setConfig("folder", f)
    }
    function close() { saveFolder(); visible = false; closed() }
    function pickModel(i) { store.setConfig("model", modelKeys[i]) }
    function pickLanguage(i) { store.setConfig("language", languageKeys[i]) }

    onOutsideTapped: close()
    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Escape || (k === Qt.Key_Comma && (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)))) close()
        else if (e.text === "m") pickModel((Math.max(0, modelKeys.indexOf(conf.model)) + 1) % modelKeys.length)
        else if (e.text === "l" && p.whisper) pickLanguage((languageKeys.indexOf(conf.language) + 1) % 3)
        else if (e.text === "t") store.setConfig("transcribe_on_save", !conf.transcribe_on_save)
        else if (e.text === "f") { folder.input.forceActiveFocus(); folder.input.selectAll() }
        else return
        e.accepted = true
    }

    Row {
        width: parent.width
        Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - escHint.width; text: "Settings"; color: p.c.title; font.family: p.c.font; font.pixelSize: 15; font.weight: Font.Medium }
        KeyCap { id: escHint; anchors.verticalCenter: parent.verticalCenter; c: p.c; keys: "esc" }
    }

    // Where recordings go: NAME.wav, its transcript and exports beside it
    AppField {
        id: folder
        width: parent.width
        c: p.c
        label: "Folder"
        hint: "f"
        onAccepted: { p.saveFolder(); p.forceActiveFocus() }
        onEscaped: { folder.text = p.conf.folder; p.forceActiveFocus() }
    }

    // z: the segments' tips hang down over the rows after them
    Column {
        z: 2
        width: parent.width
        spacing: 8
        Text { text: "Transcription"; color: p.c.text; font.family: p.c.font; font.pixelSize: 13 }
        AppSegments {
            z: 1
            c: p.c
            options: p.modelKeys.map(m => ({ label: (p.store.models[m] || {}).label || m, tip: (p.store.models[m] || {}).about || "", keys: "m" }))
            current: Math.max(0, p.modelKeys.indexOf(p.conf.model))
            onPicked: i => p.pickModel(i)
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: ({ whisper: "Whisper large-v3-turbo: the most exact, but takes about as long as the recording.",
                     medium: "Whisper medium: nearly as exact, in about two thirds of the recording's length." })[p.conf.model]
                  || "Parakeet: an hour in a few minutes, and it finds the language itself."
            color: p.c.faint; font.family: p.c.font; font.pixelSize: 11
        }
        TextEdit {
            visible: !!p.picked.missing
            width: parent.width
            readOnly: true; selectByMouse: true
            wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
            text: p.picked.missing || ""
            color: p.c.danger; font.family: p.c.font; font.pixelSize: 12
            selectionColor: p.c.accent
        }
    }

    // Parakeet can't be told the language; Whisper can, and guesses worse on its own
    Column {
        z: 1
        visible: p.whisper
        width: parent.width
        spacing: 8
        Text { text: "Whisper's language"; color: p.c.text; font.family: p.c.font; font.pixelSize: 13 }
        AppSegments {
            c: p.c
            options: [{ label: "Finnish", keys: "l" }, { label: "English", keys: "l" }, { label: "Auto", tip: "Whisper guesses: slower, and may guess wrong", keys: "l" }]
            current: Math.max(0, p.languageKeys.indexOf(p.conf.language))
            onPicked: i => p.pickLanguage(i)
        }
    }

    Row {
        spacing: 10
        AppCheck {
            c: p.c
            label: "Transcribe when saved"
            on: !!p.conf.transcribe_on_save
            // The click turned on itself: the setting is the truth from here on
            onToggled: { p.store.setConfig("transcribe_on_save", on); on = Qt.binding(() => !!p.conf.transcribe_on_save) }
        }
        KeyCap { anchors.verticalCenter: parent.verticalCenter; c: p.c; keys: "t" }
    }

    Text {
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2
        text: "Transcripts go beside the recording as NAME.txt, through your own corrections as dictation is (~/.config/voxtype/post-process)."
        color: p.c.faint; font.family: p.c.font; font.pixelSize: 11
    }
}
