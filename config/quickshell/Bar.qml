import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The top bar on every screen: workspaces on the left, the modules (TopBar, ~/.config/topbar/modules.jsonc) on the right.
// A left click opens the module's menu (shell.qml); the open menu's module is highlighted.
Variants {
    id: bar
    model: Quickshell.screens
    property string current: ""         // the open menu
    property var menus: []              // menus that exist (<Name>Menu.qml)
    property bool launcherOpen: false   // the logo is highlighted while it's open
    signal menuClicked(string menu, real x, var screen)
    signal moveStarted()                // ⌘+drag moves a module: its menu closes

    function menuOf(def) {
        const m = def.menu !== undefined ? def.menu : def.name
        return menus.indexOf(m) >= 0 ? m : ""
    }
    // Visible modules with a menu, left to right (keyboard navigation), and an icon's centre on a screen's bar (the
    // first screen's without one). The "…" (modules that don't fit) is the first, and its modules' menus open below it.
    function navOrder() {
        const w = instances[0]
        return w ? (w.moreX >= 0 ? ["overflow"] : []).concat(w.modules().filter(m => m.visible && m.hasMenu).map(m => menuOf(m.def))) : []
    }
    // A menu's place in navOrder: a menu opened from the "…" counts as the "…" (←/→ go on from there)
    function navIndex(menu) {
        const w = instances[0]
        return navOrder().indexOf(w && w.tucked.some(d => menuOf(d) === menu) ? "overflow" : menu)
    }
    function xOf(menu, screen) {
        let w = instances[0]
        for (let i = 0; i < instances.length; i++) if (screen && instances[i].modelData === screen) w = instances[i]
        if (w && w.moreX >= 0 && (menu === "overflow" || w.tucked.some(d => menuOf(d) === menu))) return w.moreX + w.moreWidth / 2
        const m = w ? w.modules().find(m => m.visible && menuOf(m.def) === menu) : null
        return m ? m.mapToItem(null, m.width / 2, 0).x : -1
    }
    // The modules in a screen's "…" and their menus, [{ def, menu }] (TopBar.overflow for its menu, shell.qml). The menus
    // are looked up here, not by layout(): the list of menus comes in after the bar's first layout.
    function tuckedOf(screen) {
        let w = instances[0]
        for (let i = 0; i < instances.length; i++) if (instances[i].modelData === screen) w = instances[i]
        return w ? w.tucked.map(d => ({ def: d, menu: menuOf(d) })) : []
    }

    delegate: PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        anchors { top: true; left: true; right: true }
        implicitHeight: Theme.barHeight
        color: TopBar.c("bg")
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "nightdrive-bar"
        readonly property real dpr: modelData.devicePixelRatio || 1
        readonly property int laptopWorkspace: 10   // hyprland.lua: LAPTOP_WORKSPACE
        readonly property bool focused: Quickshell.screens.length < 2 || !Hyprland.focusedMonitor
                                        || Hyprland.focusedMonitor.name === modelData.name
        function modules() { const out = []; for (let i = 0; i < rep.count; i++) out.push(rep.itemAt(i)); return out }

        // Workspaces 1–5 always, others while they exist; the screen's active one highlighted, empty ones dimmed.
        // The laptop's own workspace (hyprland.lua: LAPTOP_WORKSPACE, ⌘0) is a laptop icon after them, there while an
        // external display is connected or while it exists; the laptop's screen then shows only it. Number size: the `workspaces` row in adjust.conf.
        // What exists is read from the windows and the screens, not Hyprland.workspaces: a workspace given a new id
        // (⌘⌥1–0, hypr/bindings.lua) stays there under its old id with its windows, as Hyprland sends no event for it.
        Row {
            id: leftSide
            x: 10; anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            onWidthChanged: Qt.callLater(win.layout)   // the modules give way to the workspaces (layout)
            // The logo (N█) opens the launcher, for those who don't know ⌘Space yet. Settings › Top bar › Logo hides it
            // ("logo" in bar-items.json's hidden list); the Row then starts with the workspaces at the edge.
            Rectangle {
                visible: TopBar.hidden.indexOf("logo") < 0
                width: logo.width + 20; height: 27; radius: 8
                // Bright like the bar's text (a grey N looked disabled), highlighted while the launcher is open on this screen
                readonly property bool open: bar.launcherOpen && win.focused
                color: open ? TopBar.c("wsBg") : "transparent"
                // logo/nightdrive-icon-small.svg without its square: the N and the block, cut to their ink
                Image {
                    id: logo
                    readonly property real h: Math.round(TopBar.size("workspaces").size * 0.88 * win.dpr) / win.dpr   // 11 px with the default 12.5
                    function rgb(v) { const c = Qt.color(v); return "rgb(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ")\" fill-opacity=\"" + c.a }
                    x: 10; y: Math.round((parent.height - h) / 2 * win.dpr) / win.dpr
                    width: h * 19.42 / 14.13; height: h
                    sourceSize { width: Math.round(width * win.dpr); height: Math.round(height * win.dpr) }
                    source: "data:image/svg+xml;utf8," + encodeURIComponent(
                        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="6.88 8.97 19.42 14.13">'
                        + '<path fill="' + rgb(TopBar.c("hlFg")) + '" d="M6.88 22.84H9.39V16.76C9.39 15.45 9.24 13.32 9.12 12.11L12.68 22.84H16V8.97H13.49V14.67C13.49 15.98 13.66 18.32 13.8 19.7L10.21 8.97H6.88Z"/>'
                        + '<rect x="18.3" y="9.0" width="8.0" height="14.1" fill="' + rgb(Theme.primary) + '" opacity="' + (parent.open ? 1 : 0.9) + '"/></svg>')
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "launcher", "toggle"])
                }
            }
            Repeater {
                model: {
                    const ids = [1, 2, 3, 4, 5]
                    const add = w => { if (w && w.id > 0 && ids.indexOf(w.id) < 0) ids.push(w.id) }
                    for (const t of Hyprland.toplevels.values) add(t.workspace)
                    for (const m of Hyprland.monitors.values) add(m.activeWorkspace)
                    const docked = Quickshell.screens.length > 1 && Quickshell.screens.some(s => s.name.startsWith("eDP"))
                    // The laptop's screen then has only its own workspace: 1–9 are the external display's
                    if (docked && win.modelData.name.startsWith("eDP")) return [win.laptopWorkspace]
                    if (docked && ids.indexOf(win.laptopWorkspace) < 0) ids.push(win.laptopWorkspace)
                    return ids.sort((a, b) => a - b)
                }
                Rectangle {
                    id: ws
                    required property int modelData
                    readonly property bool windows: Hyprland.toplevels.values.some(t => t.workspace && t.workspace.id === modelData)
                    readonly property bool active: { const m = Hyprland.monitorFor(win.modelData); return !!m && !!m.activeWorkspace && m.activeWorkspace.id === modelData }
                    readonly property bool laptop: modelData === win.laptopWorkspace
                    readonly property color fg: active ? TopBar.c("hlFg") : windows ? TopBar.c("dim") : TopBar.c("off")
                    width: (laptop ? icon.implicitWidth : num.implicitWidth) + 20; height: 27; radius: 8
                    color: active ? TopBar.c("wsBg") : "transparent"
                    // Half while the drawer is over it, and on a screen without the focus (with more than one screen):
                    // the bright one shows where the keyboard goes
                    opacity: active && (drawer.open || !win.focused) ? 0.5 : 1
                    BarText {
                        id: num
                        visible: !ws.laptop
                        element: "workspaces"
                        dpr: win.dpr
                        x: Math.round((parent.width - implicitWidth) / 2 * win.dpr) / win.dpr
                        text: { const w = Hyprland.workspaces.values.find(w => w.id === ws.modelData); return w && w.name ? w.name : ws.modelData }   // renamed: Launcher › Rename current space
                        color: ws.fg
                    }
                    Text {
                        id: icon
                        visible: ws.laptop
                        anchors.centerIn: parent
                        text: Icons.g("laptop")
                        color: ws.fg
                        font { family: Icons.family; pixelSize: Math.round(num.sz.size * 1.1) }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + ws.modelData + " })"])
                    }
                }
            }
            // The drawer (⌘D, hypr/bindings.lua) after the workspaces, as a dot: highlighted while open on this screen, dimmed when empty
            Rectangle {
                id: drawer
                property bool open: false
                readonly property bool full: Hyprland.toplevels.values.some(t => t.workspace && t.workspace.name === "special:drawer")
                Connections {
                    target: Hyprland
                    function onRawEvent(e) {
                        if (e.name !== "activespecial") return
                        const [ws, mon] = e.data.split(",")
                        if (mon === win.modelData.name) drawer.open = ws === "special:drawer"
                    }
                }
                width: dot.implicitWidth + 20; height: 27; radius: 8
                color: open ? TopBar.c("wsBg") : "transparent"
                BarText {
                    id: dot
                    element: "workspaces"
                    dpr: win.dpr
                    x: Math.round((parent.width - implicitWidth) / 2 * win.dpr) / win.dpr
                    text: "•"
                    color: drawer.open ? TopBar.c("hlFg") : drawer.full ? TopBar.c("dim") : TopBar.c("off")
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // On this screen: the drawer opens on the focused one, and clicking the bar doesn't focus it
                    onClicked: Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "hl.dsp.focus({ monitor = \\"$1\\" })"; ' +
                                                        'hyprctl dispatch "hl.dsp.workspace.toggle_special(\\"drawer\\")"',
                                                        "sh", win.modelData.name])
                }
            }
        }

        // The modules from the right edge leftwards. On a MacBook with a notch (appledrm.show_notch=1) a module that would
        // reach under it goes, with the rest, to the notch's left side. The notch's width: the `notch` row in adjust.conf
        // (px, 0 = none), otherwise found from the internal screen's resolution.
        readonly property real notchWidth: {
            const row = TopBar.sizesLocal.notch || TopBar.sizesPublic.notch
            if (row) return row.size
            // Physical sizes with the notch shown -> its physical width (approximate, a little wider than the notch)
            const known = { "3024x1964": 400, "3456x2234": 400, "2560x1664": 360, "2880x1864": 360 }
            const phys = Math.round(modelData.width * dpr) + "x" + Math.round(modelData.height * dpr)
            return known[phys] ? known[phys] / dpr : 0
        }
        // A narrow screen: modules that would reach over the workspaces are tucked into a "…" left of the rest
        // (BarOverflow, OverflowMenu), the leftmost first: your order puts the ones you look at most near the clock.
        // The clock and ≡ always stay. With room for all, there's no "…" and the layout is the same as without it.
        readonly property var pinned: ["calendar", "notifications"]
        property var xs: []
        property var tucked: []         // the modules' defs in the "…", in the bar's order
        property real moreX: -1         // the "…"'s left edge; -1 = none
        readonly property real moreWidth: more.width
        // The modules' x from the right edge leftwards, without the ones in drop (rep's indices) and with a "…" left of
        // the rest if withMore; left = the leftmost edge used
        function place(order, drop, withMore) {
            const nl = (width - notchWidth) / 2, nr = (width + notchWidth) / 2
            let cursor = width - 10, jumped = notchWidth <= 0
            const out = []
            const put = w => {
                let x = cursor - w
                if (!jumped && x < nr) { jumped = true; cursor = nl - 6; x = cursor - w }
                cursor = x - 3
                return Math.round(x * dpr) / dpr
            }
            for (let k = order.length - 1; k >= 0; k--) {
                const i = order[k]
                const m = rep.itemAt(i)
                out[i] = !m || !m.present || drop.indexOf(i) >= 0 ? 0 : put(m.width)
            }
            const mx = withMore ? put(moreWidth) : -1
            return { xs: out, more: mx, left: cursor + 3 }
        }
        function layout() {
            const order = dragOrder.length === rep.count ? dragOrder : Array.from({ length: rep.count }, (_, i) => i)
            const limit = leftSide.x + leftSide.width + 12
            const drop = []
            let p = place(order, drop, false)
            for (const i of order) {
                if (p.left >= limit) break
                const m = rep.itemAt(i)
                if (!m || !m.present || pinned.indexOf(m.name) >= 0) continue
                drop.push(i)
                p = place(order, drop, true)
            }
            xs = p.xs
            moreX = p.more
            const t = drop.map(i => rep.itemAt(i).def)
            if (JSON.stringify(t) !== JSON.stringify(tucked)) tucked = t
        }
        onWidthChanged: Qt.callLater(layout)
        onNotchWidthChanged: Qt.callLater(layout)

        // ⌘+drag (BarModule) moves a module: it follows the pointer and the others make room; the order is saved on release
        // (TopBar.reorder: the same order as launcher › Settings › Top bar › Items). Hyprland tells when ⌘ is pressed with
        // the left button (hypr/bindings.lua): the bar has no keyboard focus to see ⌘ itself.
        property real cmdAt: 0
        Connections {
            target: Hyprland
            function onRawEvent(e) { if (e.name === "custom" && e.data === "nightdrive-cmd-press") win.cmdAt = Date.now() }
        }
        property int dragIndex: -1      // the module being moved (rep's index)
        property var dragOrder: []      // rep's indices left to right while moving
        property real dragX: 0          // its left edge
        property real grab: 0           // the pointer's offset from it
        function moveStart(i, px) {
            const m = rep.itemAt(i)
            grab = px - m.x; dragX = m.x
            dragOrder = Array.from({ length: rep.count }, (_, k) => k)
            dragIndex = i
            bar.moveStarted()
        }
        function moveTo(px) {
            const m = rep.itemAt(dragIndex)
            if (!m) return
            dragX = Math.max(0, Math.min(width - m.width, px - grab))
            const c = dragX + m.width / 2
            // Past a visible neighbour's centre: to its other side (the hidden ones between stay where they are)
            for (let n = 0; n < rep.count; n++) {
                const order = dragOrder.slice(), k = order.indexOf(dragIndex)
                const near = d => { for (let j = k + d; j >= 0 && j < order.length; j += d) if (rep.itemAt(order[j]).visible) return j; return -1 }
                const centre = j => xs[order[j]] + rep.itemAt(order[j]).width / 2
                const l = near(-1), r = near(1)
                const to = l >= 0 && c < centre(l) ? l : r >= 0 && c > centre(r) ? r : -1
                if (to < 0) break
                order.splice(k, 1); order.splice(to, 0, dragIndex)
                dragOrder = order
                layout()
            }
        }
        function moveEnd() {
            if (dragIndex < 0) return
            dragIndex = -1
            const names = dragOrder.map(i => rep.itemAt(i).name)
            // After the release's click: saving rebuilds the modules (and this one's mouse area)
            Qt.callLater(() => { TopBar.reorder(names); dragOrder = []; layout() })
        }

        Item {
            anchors.fill: parent
            Repeater {
                id: rep
                model: TopBar.modules
                onCountChanged: Qt.callLater(win.layout)
                BarModule {
                    required property var modelData
                    required property int index
                    def: modelData
                    dpr: win.dpr
                    x: win.dragIndex === index ? win.dragX : win.xs[index] || 0
                    z: win.dragIndex === index ? 1 : 0
                    Behavior on x {      // the others making room
                        enabled: win.dragIndex >= 0 && win.dragIndex !== index
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    hasMenu: bar.menuOf(modelData) !== ""
                    open: hasMenu && bar.current === bar.menuOf(modelData)
                    onLeftClicked: x => bar.menuClicked(bar.menuOf(modelData), x, win.modelData)
                    cmdAt: win.cmdAt
                    onMoveStarted: x => win.moveStart(index, x)
                    onMoveTo: x => win.moveTo(x)
                    onMoveEnded: win.moveEnd()
                    onDragOver: x => { if (hasMenu && !open) bar.menuClicked(bar.menuOf(modelData), x, win.modelData) }
                    onWidthChanged: Qt.callLater(win.layout)
                    onPresentChanged: Qt.callLater(win.layout)
                    tucked: win.tucked.some(d => d.name === modelData.name)
                }
            }
            BarOverflow {
                id: more
                visible: win.moreX >= 0
                x: win.moreX
                anchors.verticalCenter: parent.verticalCenter
                dpr: win.dpr
                open: bar.current === "overflow" || (bar.current !== "" && win.tucked.some(d => bar.menuOf(d) === bar.current))
                onClicked: x => bar.menuClicked("overflow", x, win.modelData)
            }
        }
    }
}
