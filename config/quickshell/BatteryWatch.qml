import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Low battery: a critical notification (it stays until clicked, with the urgent sound) at `warnAt` and again at `lastAt`,
// with the charge as a red meter on the card (hint value: NotificationCard.qml) and the time left when UPower knows it.
// Plugging in the charger takes the notification away. A desktop without a battery never gets one.
// From `lastAt` on, the open windows are kept each minute, so the next login can open them again if the battery runs
// out (hypr/scripts/reopen session); the charger drops them.
// Sounds (hypr/scripts/sounds event): the warning plays system/battery-low instead of the urgent chime, and plugging in
// the charger plays system/charger. Neither in do not disturb or under the login screen: they happen by themselves.
Scope {
    id: w

    // --- Tunables ---
    readonly property int warnAt: 10           // %
    readonly property int lastAt: 5            // %: the second, final warning
    readonly property string tag: "battery-low"

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev.ready && dev.isLaptopBattery
    readonly property int pct: Math.round(dev.percentage * 100)   // Quickshell gives 0–1
    readonly property bool draining: present && dev.state === UPowerDeviceState.Discharging
    // The warning level already given (0: none), so each one comes once per discharge. It survives Quickshell's reload
    // on save, so a reload doesn't warn again.
    PersistentProperties { id: given; reloadableId: "batteryWatch"; property int level: 0 }

    function check() {
        if (!present) return
        if (!draining) { if (given.level) { given.level = 0; clear(); session("drop") } return }
        const level = pct <= lastAt ? lastAt : pct <= warnAt ? warnAt : 0
        if (level === 0) { if (pct > warnAt + 2) given.level = 0; return }   // a little margin: no flapping around 10 %
        if (given.level !== 0 && given.level <= level) return
        given.level = level
        clear()   // the 5 % one comes as new (it chimes) rather than as an update of the 10 % one
        warn(level === lastAt)
    }
    function session(what) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/reopen", "session", what])
    }
    function sound(name) {
        if (!Notifs.dnd && !Notifs.locked)
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/sounds", "event", name])
    }
    // UPower's "on battery" going false is the charger plugged in (a machine without a battery never is on battery).
    // It can flap as the plug goes in (on a Mac the power controller negotiates for a moment), which
    // chimed twice: so it has to hold for `settleMs` first, and the charger chimes at most once per `chargerGap`.
    // Its first value comes as Quickshell starts and is only ever true then, so it never chimes.
    readonly property int settleMs: 1000
    readonly property int chargerGap: 5000
    property bool settledOnBattery: false
    property double lastCharger: 0
    Connections {
        target: UPower
        function onOnBatteryChanged() { settle.restart() }
    }
    Timer {
        id: settle
        interval: w.settleMs
        onTriggered: {
            const was = w.settledOnBattery
            w.settledOnBattery = UPower.onBattery
            if (was && !UPower.onBattery && w.present && Date.now() - w.lastCharger > w.chargerGap) {
                w.lastCharger = Date.now()
                w.sound("charger")
            }
        }
    }
    function clear() { Notifs.history = Notifs.history.filter(h => h.tag !== "Battery\n" + tag) }
    function warn(last) {
        const mins = dev.timeToEmpty > 0 ? Math.round(dev.timeToEmpty / 60) : 0
        const left = mins >= 60 ? Math.floor(mins / 60) + " h " + (mins % 60) + " min" : mins + " min"
        const body = pct + " % left" + (mins > 0 ? ", about " + left : "") + ". "
            + (last ? "Plug in the charger now." : "Time to plug in the charger.")
        // Straight over D-Bus like hypr/scripts/screenshot: notify-send -i sets the picture, not the app's icon
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
            "Battery", "0", "lucide:battery-warning", last ? "Battery almost empty" : "Battery low", body, "[]",
            "{'urgency': <byte 2>, 'x-dunst-stack-tag': <'" + tag + "'>, 'value': <int32 " + pct + ">, 'suppress-sound': <true>}",
            "int32 -1"])
        sound("battery-low")
    }

    Timer {
        running: w.draining && w.pct <= w.lastAt
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: w.session("save")
    }

    onPctChanged: check()
    onDrainingChanged: check()
    Component.onCompleted: { settledOnBattery = UPower.onBattery; check() }
}
