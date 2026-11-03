import QtQuick
import qs

// The look of Nightdrive's apps, in one place: the desktop's theme (Theme.qml, linked from Nightdrive's shell), with the
// terminal's background and opacity behind the window, and a few shades derived from it for lines and quiet text. An app
// makes one (`AppLook { id: c }`) and hands it to the kit's parts as `c`.
QtObject {
    readonly property color bg: Theme.launcherBg
    readonly property color solid: Qt.rgba(bg.r, bg.g, bg.b, 1)
    readonly property color line: Qt.lighter(solid, 1.45)
    readonly property color divider: Qt.lighter(line, 1.2)     // the lines between the panes
    // Under the pointer: the selected row's colour, fainter, so a row you point at never looks picked
    readonly property color hover: Qt.rgba(sel.r, sel.g, sel.b, 0.5)
    // The picked row where the keys are (active), framed only while the keys are in use (AppPointer.qml)
    property bool keyboard: false
    // Any key but a lone modifier puts the pointer's hover colour away (AppRow), as a Mac does, till the mouse moves
    // (AppPointer.qml). Not only the arrows: d or a in Mail moves the list under a resting pointer as well, and a list of
    // such keys per app would never be whole. ⌘ alone stays out, as ⌘ + a click is still the pointer's.
    property bool pointerAway: false
    // From the apps' key handlers: only the keys that move in the window (Tab, the arrows, j k) show the frame. Any key did,
    // so ⌘ alone or ⌘C over a message's selected text framed a list row, as if the keys had gone there.
    function moved(e) {
        const k = e.key
        if (k !== Qt.Key_Shift && k !== Qt.Key_Control && k !== Qt.Key_Meta && k !== Qt.Key_Alt && k !== Qt.Key_AltGr
            && k !== Qt.Key_Super_L && k !== Qt.Key_Super_R && k !== Qt.Key_Hyper_L && k !== Qt.Key_Hyper_R)
            pointerAway = true
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Left
            || k === Qt.Key_Right || (k === Qt.Key_J || k === Qt.Key_K) && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)))
            keyboard = true
    }
    readonly property color frame: keyboard ? Qt.rgba(primary.r, primary.g, primary.b, 0.5) : "transparent"
    readonly property color sel: Theme.sel
    readonly property color text: Theme.text
    readonly property color body: Qt.lighter(text, 1.06)        // long text to read (a message), a touch brighter
    readonly property color dim: Theme.dim
    readonly property color faint: Qt.darker(dim, 1.33)
    readonly property color accent: Theme.accent
    readonly property color primary: Theme.primary
    readonly property color title: Theme.title
    readonly property color danger: Theme.danger
    // Behind a panel over the window (settings, a question, the key sheet): the menus' background, dimmed
    readonly property color scrim: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.7)
    readonly property string font: Theme.font
}
