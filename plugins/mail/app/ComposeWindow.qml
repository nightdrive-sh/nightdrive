import QtQuick
import Quickshell

// Writing opens in a window of its own. To float (the default), its size is fixed while it opens, which tiling
// compositors (Hyprland, Sway) take as a dialog and float; then it is freed so the window can be resized. Set to open
// in the grid, its size is free from the start and the compositor tiles it.
// Apart from shell.qml: the writing itself is Compose.qml, and what is done with it Writing.qml.
FloatingWindow {
    id: composeWin
    required property var win
    required property var writer        // Writing.qml
    readonly property alias composer: composer
    readonly property alias autosave: autosave
    property bool done: false
    property bool opening: false
    onOpeningChanged: if (opening && !win.settings.composeFloats) opening = false
    visible: false
    minimumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(360, 400)
    // Freed, the maximum is Qt's own "none" (QWINDOWSIZE_MAX): a 0×0 maximum isn't taken as none but leaves the
    // opening size as the maximum, so Hyprland couldn't resize the window from its edges or with ⌘-drag (#3592).
    maximumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(16777215, 16777215)
    Timer { id: release; interval: 400; onTriggered: composeWin.opening = false }
    title: composer.heading
    implicitWidth: 760
    implicitHeight: 720
    color: win.look.bg
    onVisibleChanged: {
        if (visible) { done = false; release.restart(); autosave.begin() }
        else autosave.end()
        // Closed by the compositor (⌘W): nothing written is lost, so anything written goes to Drafts. Emptied of all
        // that was written, its copy saved while writing goes too.
        if (visible || done) return
        if (!composer.untouched() || composer.draftId !== "" && !composer.autoSaved) writer.saveDraft(composer.fields(), true)
        else writer.dismissCompose()
    }
    // Saved while writing: a crash or a reload of Quickshell loses only the last few seconds.
    AutoSave {
        id: autosave
        composer: composer
        mailer: composeWin.win.mailer
        onFirst: composeWin.win.reload(true)
        onFailed: error => { composer.failed = true; composer.status = error }
    }
    Compose {
        id: composer
        anchors.fill: parent
        c: win.look
        onSend: f => writer.sendMail(f)
        onSuggest: request => writer.suggest(request)
        claudeReads: win.settings.claudeReads || ""
        accounts: win.accounts
        onChooseReads: v => win.setting("claudeReads", v)
        onSave: (f, close) => writer.saveDraft(f, close)
        onDismiss: writer.dismissCompose()
        onPickFiles: win.mailer.pick(paths => composer.attach(paths))
    }
}
