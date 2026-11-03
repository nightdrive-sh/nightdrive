pragma Singleton
import qs.kit

// The top bar menus' pointer, by the apps' rule (kit/AppLook.qml, #2040): any key but a lone modifier puts the hover colour
// away (pointerAway), and only a real move of the mouse brings it back (kit/AppPointer.qml, in shell.qml's menu card).
// A mouse left resting over a menu kept its row lit beside the one the arrows (⌘⇧Space) had moved to. The menus' rows
// (MenuRow, MenuHeader, MenuButton, Ferry's) light under the mouse only while `!MenuPointer.pointerAway`. One AppLook for
// all the menus: its colours go unused here, the key rule is what is shared.
AppLook {}
