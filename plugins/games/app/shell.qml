import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Games, Nightdrive's window for the games on this computer (#3530): their covers in a grid, Enter (or the
// controller's A) plays the picked one. The list and the starting are the core's (hypr/scripts/games, through
// Store.qml); a card is GameCard.qml. The controller's Xbox button opens it in the controller's mode (`games tv`: its
// hints, A and B), and hypr/scripts/gamepad-home sends the controller's moves here over IPC (pad) while it shows.
// Once a game starts the window closes, so the game has the screen and the controller.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Games"
        implicitWidth: 1240     // as hyprland.lua's rule, which floats it in the middle
        implicitHeight: 800
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        readonly property QtObject look: c
        Store {
            id: store
            onStarted: name => { toast.show("Starting " + name + "…"); closeTimer.restart() }
            onErrorChanged: if (error !== "") toast.show(error, { danger: true })
        }
        // A moment for the toast, then away: the game's window comes up in the window's place
        Timer { id: closeTimer; interval: 900; onTriggered: Qt.quit() }

        property bool tv: false                        // the controller's mode (`games tv`): its hints, A and B
        // Sizes follow the window: the kit's own in the floating window (1240 wide), up to 1.8 times that full screen
        // (⌘⇧F), where the covers, the title and the hints are seen from further away
        readonly property real k: Math.max(1, Math.min(1.8, width / 1240))
        readonly property int coverWidth: Math.round(170 * k)
        readonly property int gap: Math.round(32 * k)
        readonly property int margin: Math.round(36 * k)
        readonly property var picked: store.games[grid.currentIndex] || null

        function play() {
            const g = picked
            if (!g || closeTimer.running) return
            store.launch(g)
        }
        function move(dir) {
            if (!store.games.length) return
            if (dir === "left") grid.moveCurrentIndexLeft()
            else if (dir === "right") grid.moveCurrentIndexRight()
            else if (dir === "up") grid.moveCurrentIndexUp()
            else if (dir === "down") grid.moveCurrentIndexDown()
        }

        IpcHandler {
            target: "games"
            // `games tv`: the controller's mode, bigger and with its hints
            function tv(on: bool): void { win.tv = on; grid.forceActiveFocus() }
            // The controller (gamepad-home): up, down, left, right, a, b. "ok"
            function pad(button: string): string {
                if (button === "a") win.play()
                else if (button === "b") Qt.quit()
                else win.move(button)
                return "ok"
            }
        }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

        // The picked game's wide picture behind everything, faint, fading into the window's colour at the foot; a game
        // without one (a game of your own with only X-Nightdrive-Cover) has its cover there, cropped to the width
        Image {
            id: hero
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: parent.height * 0.7
            readonly property string path: win.picked ? win.picked.hero || win.picked.cover || "" : ""
            source: path ? "file://" + path : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: status === Image.Ready ? 0.22 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
        Rectangle {
            anchors.fill: hero
            gradient: Gradient {
                GradientStop { position: 0.3; color: "transparent" }
                GradientStop { position: 1.0; color: c.bg }
            }
        }

        AppTitle {
            id: title
            c: c
            text: "Games"
            pixelSize: Math.round(15 * win.k)
            anchors { left: parent.left; top: parent.top; leftMargin: win.margin; topMargin: Math.round(22 * win.k) }
        }
        Text {
            anchors { right: parent.right; rightMargin: win.margin; verticalCenter: title.verticalCenter }
            text: store.games.length ? store.games.length + (store.games.length === 1 ? " game" : " games") : ""
            color: c.dim
            font { family: c.font; pixelSize: Math.round(12 * win.k) }
        }

        GridView {
            id: grid
            readonly property int columns: Math.max(1, Math.floor((win.width - 2 * win.margin) / cellWidth))
            // A row or two of covers sit in the middle, as a console's home does
            readonly property int rows: Math.ceil(store.games.length / columns)
            readonly property int room: hints.y - title.y - title.height - 16
            anchors { top: title.bottom; bottom: hints.top; bottomMargin: 16
                      topMargin: Math.max(Math.round(28 * win.k), Math.round((room - rows * cellHeight) / 2)) }
            width: Math.min(store.games.length, columns) * cellWidth
            x: Math.round((win.width - width) / 2)
            cellWidth: win.coverWidth + win.gap
            cellHeight: win.coverWidth * 1.5 + 54 + win.gap
            clip: true
            // Room inside the clip for the picked card, which grows 4 % and has its frame around it
            topMargin: 20
            bottomMargin: 20
            focus: true
            keyNavigationWraps: false
            highlightFollowsCurrentItem: true
            model: store.games
            delegate: Item {
                required property var modelData
                required property int index
                width: grid.cellWidth; height: grid.cellHeight
                GameCard {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    c: win.look
                    game: modelData
                    coverWidth: win.coverWidth
                    current: index === grid.currentIndex
                    onClicked: { grid.currentIndex = index; grid.forceActiveFocus() }
                    onDoubleClicked: { grid.currentIndex = index; win.play() }
                }
            }
            Keys.onReturnPressed: win.play()
            Keys.onEnterPressed: win.play()
            Keys.onEscapePressed: Qt.quit()   // a floating window over the desktop, gone as a launcher is
            Keys.onSpacePressed: win.play()
        }

        Text {
            anchors.centerIn: parent
            visible: store.loaded && !store.games.length
            width: Math.min(parent.width - 2 * win.margin, 520)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: "No games yet. Games you install, from Steam or as apps, show here."
            color: c.dim
            font { family: c.font; pixelSize: Math.round(14 * win.k) }
        }

        // What the keys do: the controller's in its mode, else the keyboard's
        Row {
            id: hints
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(18 * win.k) }
            spacing: Math.round(24 * win.k)
            Repeater {
                model: win.tv ? [["A", "Play"], ["B", "Close"], ["↑ ↓ ← →", "Move"]]
                              : [["⏎", "Play"], ["↑ ↓ ← →", "Move"], ["Esc", "Close"]]
                Row {
                    required property var modelData
                    spacing: 8
                    KeyCap { c: win.look; keys: modelData[0]; capSize: Math.round(22 * win.k); anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[1]
                        color: c.dim
                        font { family: c.font; pixelSize: Math.round(12 * win.k) }
                    }
                }
            }
        }

        AppToast { id: toast; c: win.look }
    }
}
