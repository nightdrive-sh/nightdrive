import QtQuick
import Quickshell
import Quickshell.Io

// Sending in the background: Send closes the writing window at once and the message goes from here. Each job is
// { f (the writing window's fields), heading, replyId, forwardId, state "sending" or "failed", error }. A message that
// fails is saved in Drafts, so it isn't lost if Mail quits; the main window's sidebar (SendStatus.qml) offers Retry and
// Open, and with only the writing window (a mailto: link, `nightmail new`) a notification does.
QtObject {
    id: box
    required property QtObject nm
    property var jobs: []
    readonly property bool busy: jobs.some(j => j.state === "sending")
    readonly property var failedJob: jobs.find(j => j.state === "failed") ?? null
    // With no main window to show it in, a failure is a notification (set by shell.qml: the main window's visibility)
    property bool notifyFailures: false

    signal sent(var job)            // shell.qml tags what was answered and reloads
    signal reopen(var job)          // Open: back into the writing window
    signal idle()                   // nothing sending or failed is left: Mail started for one message may quit

    readonly property string sound: Quickshell.env("HOME") + "/.local/share/nightdrive/sounds/mail/sent.wav"
    readonly property string player: Quickshell.env("HOME") + "/.config/hypr/scripts/sounds"

    // Jobs are found again by id: a var property may hand back a copy of the object, not the same one
    property int nextId: 0
    // The swoosh plays as Send is pressed, not once the message has gone: a failure says so on its own (Drafts, "Not sent").
    function send(f, heading, replyId, forwardId) {
        chime()
        const job = { id: nextId++, f: f, heading: heading, replyId: replyId, forwardId: forwardId, state: "sending", error: "" }
        jobs = jobs.concat([job])
        run(job.id)
    }
    function retry(job) { run(job.id) }
    function open(job) { reopen(get(job.id)); drop(job.id) }     // reopened first: the writing window keeps Mail from quitting

    function get(id) { return jobs.find(j => j.id === id) }
    function update(id, change) { jobs = jobs.map(j => j.id === id ? Object.assign({}, j, change) : j) }
    function drop(id) { jobs = jobs.filter(j => j.id !== id); if (!jobs.length) idle() }

    function run(id) {
        update(id, { state: "sending", error: "" })
        nm.compose(["send", JSON.stringify(get(id).f)], r => {
            // Tagged before it leaves the list: with Mail started for this message alone, an empty list quits it
            if (!r.error) { sent(get(id)); drop(id); return }
            // Kept in Drafts until it goes: the new copy replaces the one saved before (draft_id), and sending drops it.
            // It shows as failed (Retry, Open) only once saved, so Open writes on the new copy.
            nm.compose(["draft", JSON.stringify(get(id).f)], d => {
                if (!get(id)) return
                update(id, { state: "failed", error: r.error, f: d.error ? get(id).f : Object.assign({}, get(id).f, { draft_id: d.id }) })
                if (notifyFailures) notify(get(id))
            })
        })
    }

    // The sound plays as notifications' do (hypr/scripts/sounds: on headphones or the Mac's speakers, at their
    // volume), and not under Do Not Disturb, which the desktop's Quickshell holds.
    function chime() {
        Quickshell.execDetached(["bash", "-c", '[[ $(qs ipc call notifications getDnd 2>/dev/null) == true ]] || exec "$1" file "$2"',
                                 "chime", player, sound])
    }

    readonly property Component notice: Component {
        Process {
            id: p
            property var job
            running: true
            command: ["notify-send", "--app-name=Mail", "--icon=nightmail", "--hint=string:desktop-entry:nightmail", "--urgency=critical",
                      "--action=default=Open", "--action=retry=Retry", "--wait",
                      "Not sent: " + (job.f.subject || "(no subject)"), job.error + "\nIt is kept in Drafts."]
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim()
                    if (a === "retry") box.retry(p.job)
                    else if (a === "default") box.open(p.job)
                    else box.drop(p.job.id)     // dismissed: it waits in Drafts
                    p.destroy()
                }
            }
        }
    }
    function notify(job) { notice.createObject(box, { job: job }) }
}
