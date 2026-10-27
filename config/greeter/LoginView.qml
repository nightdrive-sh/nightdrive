import QtQuick
import Quickshell
import Quickshell.Io

// The login screen's look, shared by the greeter (shell.qml, greetd) and the lock at startup (lock.qml): wallpaper, logo,
// password prompt, an error line and the sounds. The caller does the authentication and sets busy/message (and clears
// message on typing).
Item {
    id: view

    property bool busy: false
    property string message: ""
    signal submitted(string password)
    signal escapePressed()
    signal typing()

    readonly property string title: "Nightdrive"
    readonly property string wallpaper: Quickshell.shellDir + "/background.jpg"
    // The beeps (sounds/generate.py: keys/); the greeter has its copy in /etc/greetd/greeter/sounds
    readonly property string sounds: Quickshell.shellDir + "/sounds/"
    // An error line (a wrong password) plays system/error.wav. The greeter has it with the beeps (keys/error.wav is a
    // link to it, so install.sh copies it too); lock.qml plays it through hypr/scripts/sounds instead, so Settings ›
    // Notifications › System sounds silences it there.
    property var errorCommand: ["pw-play", "--volume", "0.7", "-P", "{ node.dont-move = true }", sounds + "error.wav"]
    onMessageChanged: if (message !== "" && main) Quickshell.execDetached(errorCommand)

    readonly property color bg: "#1a1b26"
    readonly property color text: "#c0caf5"
    readonly property color accent: "#e0bff2"
    readonly property color violet: "#c071eb"
    readonly property color danger: "#f7768e"
    readonly property string font: "JetBrains Mono"
    readonly property int promptSize: 20
    readonly property real cell: 0.6 * promptSize      // a character cell of the monospaced font
    property bool promptShown: false
    // Under the lock every screen has a view, but the keyboard goes to one (the focused monitor): only that one shows the
    // logo and prompt, the others the wallpaper. The startup sound plays once, from the view that is main at the start;
    // the others run their intro unseen, so a view that becomes main later shows its prompt straight away.
    property bool main: true
    // false: the prompt straight away, without the logo typing itself in or the sounds (a lock later in the session)
    property bool intro: true
    onMainChanged: { if (main) input.forceActiveFocus(); view.decideSound() }

    // node.dont-move: EasyEffects (started with the session, under this lock) moves every stream into its own sink, and at
    // boot that sink isn't linked to the output yet, so the startup sound went nowhere. These go straight to the output.
    function beep(name) {
        if (view.main && view.intro)
            Quickshell.execDetached(["pw-play", "--volume", "0.7", "-P", "{ node.dont-move = true }", view.sounds + name + ".wav"])
    }
    // The startup sound as the screen appears (it swells in slowly while the logo's cursor waits), a PC's power-on beep
    // as the prompt is printed
    onPromptShownChanged: if (promptShown) beep("prompt")

    // At boot the screen comes up before PipeWire has its outputs, and a sound started then went nowhere: the startup
    // sound waits (at most 4 s) for the default output, on a Mac (asahi-audio) for the speakers' filter, the headphone jack
    // or Bluetooth: the raw speakers come before the filter. The logo is timed to the sound, so it starts typing as the sound starts.
    property bool soundStarted: false
    Process {
        id: startupSound
        command: ["sh", "-c", `
            i=0
            while [ $i -lt 40 ]; do
                case $(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | sed -n 's/^.* node.name = "\\(.*\\)"$/\\1/p') in
                    audio_effect.*|bluez_*|*Headphones*) break ;;
                    ?*) [ -d /usr/share/asahi-audio ] || break ;;
                esac
                sleep 0.1; i=$((i + 1))
            done
            [ $i -gt 0 ] && sleep 0.3    # just came up: a moment for it to be linked to the speakers
            echo playing
            exec pw-play --volume 0.7 -P "{ node.dont-move = true }" "$1"`, "sh", view.sounds + "startup.wav"]
        stdout: SplitParser { onRead: view.soundStarted = true }
    }
    Timer { interval: 4500; running: !view.soundStarted; onTriggered: view.soundStarted = true }
    // Which view plays it is decided once, at the start. Under the lock the surface's screen (and so main) is set only
    // after the view is created: main was still false here, and the sound never played at boot. So a view that isn't main
    // yet waits a moment before giving the sound up.
    property bool soundDecided: false
    function decideSound() {
        if (soundDecided || !main || !intro) return
        soundDecided = true
        soundWait.stop()
        startupSound.running = true
    }
    Timer { id: soundWait; interval: 300; onTriggered: { view.soundDecided = true; view.soundStarted = true } }
    Component.onCompleted: {
        if (!view.intro) view.soundStarted = true
        else if (!view.soundDecided) { soundWait.start(); view.decideSound() }
        if (!view.intro) { logo.finish(); view.promptShown = true }
    }

    // Gives the keyboard back to the field after busy (a disabled TextInput loses its focus)
    onBusyChanged: if (!busy) input.forceActiveFocus()

    Rectangle { anchors.fill: parent; color: view.bg }
    // Already darkened in the middle (background.sh)
    Image {
        anchors.fill: parent
        source: view.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    // A retro prompt: the logo types itself in, its cursor flashes and fades, then PASSWORD? is printed with a cursor of
    // its own: one cursor on screen at a time.
    // Errors read like a C64's (?WRONG PASSWORD ERROR) on the line above the prompt.
    // Everything is centred on the logo's letters (so its cursor going out moves nothing): PASSWORD?, and what you type on
    // the line below it, with the cursor after it ("***█" centred as a whole).
    Item {
        id: stage
        visible: view.main
        anchors.centerIn: parent
        width: parent.width
        height: logo.height + 34 + promptBlock.height
        readonly property real centre: logo.x + logo.textWidth / 2

        NightdriveLogo {
            id: logo
            x: Math.round((parent.width - textWidth) / 2)
            name: view.title
            pixelSize: 44
            // N appears with the startup sound's first sparkle: 0.5 s into the sound, plus ~100 ms for pw-play to reach
            // the speakers (~65 ms measured at the sink, the rest by ear: the speakers' own processing)
            startDelay: 600
            started: view.soundStarted
            blinks: false
            flashes: true
            keepsCursor: !view.promptShown      // the cursor moves down to the prompt when that shows
        }
        // After its white flash the logo's cursor fades out, then the prompt is printed with the cursor of its own
        SequentialAnimation {
            running: logo.done
            PauseAnimation { duration: 330 }            // the flash (NightdriveLogo: 70 ms white, 260 ms back)
            NumberAnimation { target: logo; property: "cursorOpacity"; to: 0; duration: 600; easing.type: Easing.InOutQuad }
        }
        // A moment after the name is typed, the prompt is printed
        Timer {
            interval: 1400
            running: logo.done && !view.promptShown
            onTriggered: view.promptShown = true
        }

        Column {
            id: promptBlock
            y: logo.height + 34
            spacing: 10
            visible: view.promptShown

            Text {
                x: Math.round(stage.centre - implicitWidth / 2)
                height: 22
                text: view.message === "" ? "" : view.message === "Wrong password" ? "?WRONG PASSWORD ERROR"
                                                                                   : "?" + view.message.toUpperCase()
                color: view.danger
                font { family: view.font; pixelSize: view.promptSize }
            }

            Text {
                id: label
                x: Math.round(stage.centre - implicitWidth / 2)
                text: "PASSWORD?"
                color: view.accent
                font { family: view.font; pixelSize: view.promptSize; weight: Font.Bold }
            }

            // Room for ~24 characters; a longer password scrolls. Half a cell to the left, for the cursor after the text.
            Item {
                x: Math.round(stage.centre - width / 2 - view.cell / 2)
                width: 24 * view.cell; height: input.implicitHeight
                clip: true

                TextInput {
                    id: input
                    width: parent.width
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "*"
                    passwordMaskDelay: 0
                    color: view.text
                    selectionColor: "#35253d"
                    // No ligatures: JetBrains Mono draws *** as one shape, its middle star raised
                    font { family: view.font; pixelSize: view.promptSize; weight: Font.Bold; features: { "liga": 0, "calt": 0 } }
                    enabled: !view.busy
                    focus: true
                    onAccepted: { if (text !== "" && !view.busy) view.submitted(text); text = "" }
                    Keys.onEscapePressed: view.escapePressed()
                    // A beep per key press, the return key's too
                    Keys.onPressed: event => {
                        if (!view.busy && !event.isAutoRepeat && (event.text !== "" || event.key === Qt.Key_Backspace))
                            view.beep("key")
                    }
                    onTextChanged: if (text !== "") { logo.finish(); view.promptShown = true; view.typing() }

                    // A block cursor, a character cell wide; it blinks faster while the password is checked
                    cursorDelegate: Rectangle {
                        width: view.cell; height: input.cursorRectangle.height
                        color: view.violet
                        // Lights up when the logo's cursor goes out: one cursor on screen at a time. Opacity, not
                        // visible: TextInput sets its cursor's visible itself
                        opacity: view.promptShown && (input.activeFocus || view.busy) && blinker.lit ? 1 : 0

                        QtObject { id: blinker; property bool lit: true }
                        Timer {
                            id: blinkTimer
                            interval: view.busy ? 120 : 550; repeat: true; running: true
                            onTriggered: blinker.lit = !blinker.lit
                        }
                        // Typing keeps it lit, like a real cursor
                        Connections {
                            target: input
                            function onTextChanged() { blinker.lit = true; blinkTimer.restart() }
                        }
                        // ... and it starts lit when the prompt is printed
                        Connections {
                            target: view
                            function onPromptShownChanged() { blinker.lit = true; blinkTimer.restart() }
                        }
                    }
                }
            }
        }
    }
}
