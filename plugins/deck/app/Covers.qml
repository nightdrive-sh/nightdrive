import QtQuick
import Quickshell.Io

// Album covers and artists' pictures by URI: the image's address from Spotify's oEmbed (no sign-in needed), asked once
// per album or artist when a row shows it. The addresses are kept in covers.json, so a cover shows at once the next time;
// the images themselves aren't kept (Spotify's CDN serves them, as to its own apps). Its own file as it is a cache with
// its own requests, used by every view and the header.
Item {
    id: root
    required property var win

    property var urls: ({})
    property bool loaded: false
    property var asked: ({})                    // this session's oEmbed requests: one per album
    FileView {
        id: file
        path: root.win.home + "/.cache/deck/covers.json"
        printErrors: false
        onLoaded: { try { root.urls = JSON.parse(text()) } catch (e) {} root.loaded = true }
        onLoadFailed: root.loaded = true
    }
    Timer { id: save; interval: 1000; onTriggered: file.setText(JSON.stringify(root.urls) + "\n") }
    function cover(uri) {
        if (urls[uri]) return urls[uri]
        if (!loaded || asked[uri]) return ""
        asked[uri] = true
        const [, kind, id] = uri.split(":")
        const req = new XMLHttpRequest()
        req.onreadystatechange = () => {
            if (req.readyState !== XMLHttpRequest.DONE || req.status !== 200) return
            try {
                const url = JSON.parse(req.responseText).thumbnail_url
                if (!url) return
                const c = Object.assign({}, urls); c[uri] = url; urls = c
                save.restart()
            } catch (e) {}
        }
        req.open("GET", "https://open.spotify.com/oembed?url=https://open.spotify.com/" + kind + "/" + id)
        req.send()
        return ""
    }
}
