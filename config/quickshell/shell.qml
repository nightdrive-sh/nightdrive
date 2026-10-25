// Quickshell – the top bar (Bar.qml, data in TopBar.qml / ~/.config/topbar) and its menus.
// Clicking a bar module opens its menu below it; a shortcut opens one with  qs ipc call menu toggle <name>  (below its icon too,
// or at the right edge if it has none).
// `qs ipc call bar refresh` updates every bar module now (after a change a module's status would only see later).
// Menus live in <Name>Menu.qml files; shared parts: Theme, Icons, Sh, MenuHeader, MenuRow, MenuSection, MenuNote, Slider.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: root
    property string current: ""
    property real anchorX: -1          // icon's horizontal coordinate (logical px); -1 = right edge

    // --- Keyboard navigation (⌘⇧Space): ←/→ switch menu (in the bar's order), ↑/↓ select a row, Enter activates, Esc closes ---
    property bool navMode: false
    // Menus: <Name>Menu.qml here, a private overlay's in local/ (not in the repo; its bar modules come from
    // ~/.config/topbar/local.modules.jsonc) and the installed plugin folders' (TopBar.plugin.menus: name → path).
    // local/LauncherExtension.qml extends the launcher.
    property var ownMenus: []
    readonly property var menus: ownMenus.concat(Object.keys(TopBar.plugin.menus))
    property var localMenus: []
    property bool localLauncher: false
    Sh {
        command: ["bash", "-c", 'cd "$1" && ls; echo --; ls local 2>/dev/null', "_", Quickshell.shellDir]
        running: true
        onResult: text => {
            const parts = text.split("--\n")
            const names = t => (t || "").split("\n").filter(f => /^[A-Z]\w*Menu\.qml$/.test(f)).map(f => f.charAt(0).toLowerCase() + f.slice(1, -8))
            root.localMenus = names(parts[1])
            root.ownMenus = names(parts[0]).concat(root.localMenus)
            root.localLauncher = (parts[1] || "").split("\n").indexOf("LauncherExtension.qml") >= 0
        }
    }
    property var menuScreen: null      // the screen whose bar was clicked, or the focused one (a shortcut, ⌘⇧Space)
    // The screen Hyprland has the focus on: a menu opened by a key comes up there, not on the first screen
    function focusedScreen() {
        const f = Hyprland.focusedMonitor
        return (f && Quickshell.screens.find(s => s.name === f.name)) || Quickshell.screens[0]
    }
    property bool viaSubmap: false     // opened by click/shortcut: ←/→/↑/↓/Enter/Esc come from a Hyprland submap (hypr/bindings.lua: qsmenu), no keyboard focus
    property var navItem: null         // selected row / toggle

    function submap(name) { Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("' + name + '")']) }
    Component.onCompleted: submap("reset")      // safety net: in case the previous session was left in the submap

    // A reload on save or a restart only shows as the bar redrawing (an open menu closes), easy to miss: a short silent
    // popup says it happened. Not at login: qs's PID (the parent of this Process, not of an execDetached one) kept in the
    // runtime dir tells a reload (same PID) from a restart (another) from the session's first start (none). The sleep gives
    // a restarted qs time to own the notification service again.
    Sh {
        running: true
        command: ["bash", "-c", `
            prev=$(cat "$1" 2>/dev/null); echo "$PPID" > "$1"
            [ -n "$prev" ] || exit 0
            [ "$prev" = "$PPID" ] && msg="The top bar reloaded" || msg="The top bar restarted"
            sleep 1; notify-send -e -u low -a Quickshell "$msg"`, "_", Quickshell.env("XDG_RUNTIME_DIR") + "/nightdrive-qs.pid"]
    }
    Connections {
        target: Quickshell
        function onReloadFailed(error) {
            Quickshell.execDetached(["notify-send", "-e", "-a", "Quickshell", "The top bar didn't reload", error.split("\n")[0]])
        }
    }

    onCurrentChanged: {
        navItem = null
        if (current === "") { navMode = false; viaSubmap = false }
        submap(current !== "" && viaSubmap ? "qsmenu" : "reset")
    }
    function openNav(i) {
        const order = bar.navOrder()
        const n = order.length
        if (n === 0) return
        const name = order[((i % n) + n) % n]
        menuScreen = focusedScreen()
        anchorX = bar.xOf(name, menuScreen)
        current = name
    }
    function navToggle() {
        if (navMode) { current = ""; return }
        viaSubmap = false
        navMode = true
        openNav(Math.max(0, bar.navIndex(current)))
        keyItem.forceActiveFocus()
    }
    function navRows() {
        const out = []
        const walk = it => {
            for (const c of it.children) {
                if (!c.visible) continue
                if (typeof c.navActivate === "function" && c.navEnabled !== false && c.height > 0) out.push(c)
                walk(c)
            }
        }
        if (loader.item) walk(loader.item)
        out.sort((a, b) => navY(a) - navY(b))
        return out
    }
    // The scrolling list (Flickable, ListView) a row is in, or null
    function flickOf(it) {
        for (let p = it.parent; p; p = p.parent)
            if (p.contentItem !== undefined && p.contentY !== undefined) return p
        return null
    }
    // A row's place in the menu, top to bottom. A row in a scrolling list counts within the list's own box, so a row
    // scrolled out of sight still comes before the rows under the list
    function navY(it) {
        const f = flickOf(it)
        if (!f) return it.mapToItem(card, 0, 0).y
        const y = it.mapToItem(f.contentItem, 0, 0).y
        return f.mapToItem(card, 0, 0).y + y / Math.max(1, f.contentHeight) * f.height
    }
    function navShow(it) {
        const f = flickOf(it)
        if (!f) return
        const y = it.mapToItem(f.contentItem, 0, 0).y
        if (y < f.contentY) f.contentY = y
        else if (y + it.height > f.contentY + f.height) f.contentY = y + it.height - f.height
    }
    function navMove(d) {
        const rows = navRows()
        if (rows.length === 0) return
        let i = rows.indexOf(navItem)
        i = i < 0 ? (d > 0 ? 0 : rows.length - 1) : (i + d + rows.length) % rows.length
        if (navItem) navItem.navSelected = false
        navItem = rows[i]
        navItem.navSelected = true
        navShow(navItem)
    }
    function navAct(a) {     // a: left | right | up | down | enter
        if (!navMode) return false
        if (a === "left")       openNav(bar.navIndex(current) - 1)
        else if (a === "right") openNav(bar.navIndex(current) + 1)
        else if (a === "up")    navMove(-1)
        else if (a === "down")  navMove(1)
        else if (a === "enter") { if (navItem) navItem.navActivate() }
        else if (a === "esc")   current = ""
        else return false
        return true
    }
    function navKey(event) {
        const a = { [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Return]: "enter", [Qt.Key_Enter]: "enter", [Qt.Key_Escape]: "esc" }[event.key]
        if (a && navAct(a)) event.accepted = true
    }
    IpcHandler {
        target: "menu"
        // toggleAt: x = the icon's centre, the menu opens below it (the bar calls clickMenu directly)
        function toggleAt(name: string, x: int): void { root.clickMenu(name, x, null) }
        // toggle: opened by a shortcut (e.g. ⌘Esc -> power). Opens in keyboard mode so Esc closes and arrows/Enter work.
        function toggle(name: string): void {
            // Only a menu that exists: a plugin's isn't listed while the plugin isn't installed
            if (root.current !== name && root.menus.indexOf(name) < 0) return
            root.menuScreen = root.focusedScreen()
            root.anchorX = bar.xOf(name, root.menuScreen)      // below its bar icon; -1 (no icon in the bar) = the right edge
            const opening = root.current !== name
            root.viaSubmap = opening
            root.navMode = opening
            root.current = opening ? name : ""
        }
        function close(): void { root.current = "" }
        function nav(): void { root.navToggle() }
        function navkey(a: string): string { root.navAct(a); return root.current + " | " + (root.navItem ? (root.navItem.label || root.navItem.title || "?") : "-") }   // testing / scripts
    }

    IpcHandler {
        target: "bar"
        function refresh(): void { TopBar.refresh("") }
        function refreshModule(name: string): void { TopBar.refresh(name) }
        // Hyprland sends no event when a workspace gets a new id (⌘⌥1–0, hypr/bindings.lua): read them again, and the
        // windows too, which still point at the old workspace (the bar's numbers would show it empty)
        function workspaces(): void { Hyprland.refreshWorkspaces(); Hyprland.refreshMonitors(); Hyprland.refreshToplevels() }
    }

    // A click on a bar module. The menu also enters keyboard mode (Esc closes, arrows/Enter work as with ⌘⇧Space).
    function clickMenu(name, x, screen) {
        anchorX = x
        menuScreen = screen
        const opening = current !== name
        // The Wifi menu has a password field that needs real keyboard focus: no arrow-key navigation
        viaSubmap = opening && name !== "wifi"
        navMode = viaSubmap
        current = opening ? name : ""
    }

    Bar {
        id: bar
        current: root.current
        menus: root.menus
        launcherOpen: launcher.open
        onMenuClicked: (name, x, screen) => root.clickMenu(name, x, screen)
        onMoveStarted: root.current = ""
    }
    // The "…" menu lists the modules that didn't fit on its screen's bar
    Binding { target: TopBar; property: "overflow"; value: bar.tuckedOf(root.menuScreen) }

    Osd {}

    NotificationPopups {}

    BatteryWatch {}

    Picker {}

    PowerDialog {}

    AirPodsSettings {}

    ThemeEditor {}

    SharePicker {}

    ClaudeWrite {}

    Drawer {}

    Shelf {}

    PolkitWatch { id: polkit }

    Launcher {
        id: launcher
        stepAside: polkit.asking
        extSource: root.localLauncher ? "local/LauncherExtension.qml" : ""
        onOpenMenu: name => { root.menuScreen = root.focusedScreen(); root.anchorX = bar.xOf(name, root.menuScreen); root.current = name }   // below its bar icon (-1 = none: right edge)
    }

    PanelWindow {
        visible: root.current !== "" && !polkit.asking   // the password prompt is a window: it can't get above an overlay
        screen: root.menuScreen || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        margins { top: Theme.barHeight }   // the top bar stays clickable
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "nightdrive-menu"   // hyprland.lua blurs behind a bare menu's translucent cards
        // Keyboard focus only for a text field: the wifi menu's password, or a menu that asks for it while it shows one
        // (wantsKeyboard: Ferry's text). With OnDemand all the time a second click on the top bar was lost until the
        // mouse was moved.
        WlrLayershell.keyboardFocus: root.navMode && !root.viaSubmap ? WlrKeyboardFocus.Exclusive
            : (root.current === "wifi" || (loader.item && loader.item.wantsKeyboard === true) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

        // A menu dragging a file out (FerryMenu, NotificationsMenu: dragging > 0) takes input only on its card meanwhile, so the drop reaches
        // the windows below
        mask: loader.item && loader.item.dragging > 0 ? cardMask : null
        property Region cardMask: Region { item: card }

        // Clicking outside the menu closes it
        MouseArea { anchors.fill: parent; onClicked: root.current = "" }
        Item { id: keyItem; anchors.fill: parent; focus: true; Keys.onEscapePressed: root.current = ""; Keys.onPressed: event => root.navKey(event) }

        Rectangle {
            id: card
            // A bare menu (property bare: true, e.g. NotificationsMenu) draws its own cards: no background or padding here
            readonly property bool bare: loader.item ? loader.item.bare === true : false
            anchors { top: parent.top; topMargin: card.bare ? 10 : 6 }
            width: loader.item && loader.item.preferredWidth ? loader.item.preferredWidth : 320   // a menu can request a wider card
            // Center below the icon, but keep a 10 px margin from the screen edges
            x: root.anchorX < 0 ? parent.width - width - 10
                                : Math.max(10, Math.min(parent.width - width - 10, root.anchorX - width / 2))
            height: loader.item ? loader.item.implicitHeight + (bare ? 0 : 26) : 0   // 10 px top and 16 px bottom margin
            radius: 10
            color: bare ? "transparent" : Theme.bg
            border.width: 0   // no border (the dividers inside the menu stay)
            Keys.onEscapePressed: root.current = ""

            MouseArea { anchors.fill: parent }   // a click inside the card doesn't close the menu

            Loader {
                id: loader
                anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: card.bare ? 0 : 16; rightMargin: card.bare ? 0 : 16
                          topMargin: card.bare ? 0 : 10 }
                source: root.current === "" ? ""
                      : TopBar.plugin.menus[root.current] ? "file://" + TopBar.plugin.menus[root.current]
                      : (root.localMenus.indexOf(root.current) >= 0 ? "local/" : "") + root.current.charAt(0).toUpperCase() + root.current.slice(1) + "Menu.qml"
            }
            Connections {
                target: loader.item
                ignoreUnknownSignals: true
                function onClose() { root.current = "" }
                function onOpenMenu(name) { root.current = name }   // the "…" menu (OverflowMenu): a module's, in its place
            }
        }
    }
}
