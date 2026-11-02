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
    property bool done: false
    property bool opening: false
    onOpeningChanged: if (opening && !win.settings.composeFloats) opening = false
    visible: false
    minimumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(360, 400)
    maximumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(0, 0)
    Timer { id: release; interval: 400; onTriggered: composeWin.opening = false }
    title: composer.heading
    implicitWidth: 760
    implicitHeight: 720
    color: win.look.bg
    onVisibleChanged: {
        if (visible) { done = false; release.restart() }
        // Closed by the compositor (⌘W): nothing written is lost, so anything written goes to Drafts.
        else if (!done && (composer.draftId !== "" || !composer.untouched())) writer.saveDraft(composer.fields(), true)
        else if (!done) writer.composeEnded()
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
