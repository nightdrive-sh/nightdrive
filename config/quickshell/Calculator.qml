import QtQuick
import Quickshell
import Quickshell.Io

// The launcher's calculator, like Spotlight: a root search that looks like a calculation ("3*8", "5 km in miles",
// "100 eur in usd", "15% of 80") gets "= 24" as a row, Enter copies the result. qalc (libqalculate, the qalculate package)
// does the maths, units and currencies; without it there is simply no row.
// Safety and speed: the query goes to qalc as an argument (no shell), with a timeout, debounced, and only the answer to
// the latest query is shown. qalc runs on a config of its own (XDG_CONFIG_HOME below), so the user's qalc settings don't
// change the results, mixed units stay off ("3.1 mi", not "3 mi + 188 yd"), and it never fetches exchange rates
// itself: they are refreshed here at most once a day, in the background (qalc keeps them in ~/.local/share/qalculate).
Item {
    id: c
    required property var launcher

    readonly property int debounceMs: 150
    readonly property int timeoutS: 2
    readonly property int rateAgeMin: 24 * 60
    readonly property string cfgHome: Quickshell.env("HOME") + "/.cache/nightdrive/qalc"
    readonly property string ratesFile: Quickshell.env("HOME") + "/.local/share/qalculate/rates.json"

    property bool have: false            // qalc is installed
    property string expr: ""             // what the current query asks of qalc ("" = not a calculation)
    property string asked: ""            // the expression qalc is working on
    property bool busy: false            // asked, its answer not read yet
    property string forExpr: ""          // the expression `answer` belongs to
    property string answer: ""
    property bool ratesChecked: false

    // "3,5*2" → "3.5*2" etc. Returns "" when the query doesn't look like a calculation: then normal searches ("1password",
    // "fm-84", "7-zip") never reach qalc. qalc itself would read nearly anything as units ("hello" = e·B·h·L²).
    function toExpr(q) {
        let t = q.trim()
        if (t.length < 2 || t.length > 200 || !/\d/.test(t)) return ""
        if (/^\d{4}-\d\d-\d\d$/.test(t)) return ""                       // a date, not 2026 − 10 − 25
        if (!/^([\d(.√+\-$€£]|(sqrt|cbrt|abs|round|floor|ceil|ln|log|exp|sin|cos|tan)\()/i.test(t)) return ""
        const conv = /\s(to|in)\s+[^\d\s]/i.test(t)
        if (!conv && !/[+\-*/×÷^%!√()]/.test(t)) return ""
        t = t.replace(/(\d),(\d)/g, "$1.$2")                             // decimal comma in: qalc reads a point
             .replace(/×/g, "*").replace(/÷/g, "/")
             .replace(/(\d)\s*x\s*(\d)/gi, "$1*$2")                        // 2 x 3
             .replace(/%\s*of\s+/gi, "% * ")                              // 15% of 80 (qalc: rem)
             .replace(/\s+in\s+([^\d\s][^\d]*)$/i, " to $1")               // "in" is inches to qalc
        return t
    }

    // The row for the current query, or null; the launcher puts it before the search's hits
    function row(q) {
        const e = toExpr(q)
        if (e === "" || e !== forExpr || answer === "") return null
        return { kind: "calc", name: "= " + answer, sub: q.trim(), glyph: "calculator", copy: answer }
    }

    // Trailing zeros off ("$116.9200000" → "$116.92"), then the decimal mark of Settings › Launcher
    function tidy(s) {
        s = s.trim().replace(/(\.\d*?[1-9])0+(?!\d)/g, "$1").replace(/\.0+(?!\d)/g, "")
        return launcher.prefs.comma ? s.replace(/(\d)\.(\d)/g, "$1,$2") : s
    }

    onExprChanged: if (expr !== "") debounce.restart()
    Binding { target: c; property: "expr"; value: c.have && c.launcher.open && c.launcher.level === "root" ? c.toExpr(c.launcher.query) : "" }
    Timer { id: debounce; interval: c.debounceMs; onTriggered: c.run() }

    function run() {
        if (expr === "" || expr === forExpr || busy || proc.running) return   // a busy qalc: asked again when it's done
        if (!ratesChecked) { ratesChecked = true; rates.running = true }
        asked = expr; busy = true
        // The query is $1, an argument: never part of the script. The exit code comes after the answer, as stdout's
        // end and the process's exit can arrive in either order
        proc.command = ["bash", "-c", 'timeout "$2" qalc -t -- "$1" 2>/dev/null; echo "__EXIT:$?"', "_", expr, String(timeoutS)]
        proc.running = true
    }

    Process {
        id: proc
        environment: ({ XDG_CONFIG_HOME: c.cfgHome })
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/__EXIT:(\d+)\s*$/)
                const r = text.replace(/__EXIT:\d+\s*$/, "").trim()
                // An error, a timeout, or the question back unsolved ("10 / 0") is no answer
                const ok = m && m[1] === "0" && r !== "" && !/\n/.test(r) && r.replace(/\s/g, "") !== c.asked.replace(/\s/g, "")
                c.forExpr = c.asked; c.answer = ok ? c.tidy(r) : ""; c.busy = false
                Qt.callLater(c.run)
            }
        }
        onRunningChanged: if (!running) Qt.callLater(c.run)
    }

    // Is qalc there; its config: mixed units off, no fetching by itself. Written at every start, as qalc saves its
    // settings back on exit.
    Process {
        running: true
        command: ["bash", "-c", 'command -v qalc >/dev/null && mkdir -p "$1/qalculate" && printf "[General]\\nmixed_units_conversion=0\\nauto_update_exchange_rates=0\\n" > "$1/qalculate/qalc.cfg"', "_", c.cfgHome]
        onExited: code => c.have = code === 0
    }
    // Exchange rates older than a day: fetched once per session, when the first calculation is asked
    Process {
        id: rates
        environment: ({ XDG_CONFIG_HOME: c.cfgHome })
        command: ["bash", "-c", '[ -n "$(find "$1" -mmin -"$2" 2>/dev/null)" ] || timeout 30 qalc -e -t 1 >/dev/null 2>&1', "_", c.ratesFile, String(c.rateAgeMin)]
    }
}
