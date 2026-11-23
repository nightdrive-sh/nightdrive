import QtQuick
import QtQuick.Window

// The big preview's picture (QuickLookBody): as large as fits but never past its own size, so a small icon isn't blown
// up into a blur. The wheel (a touchpad's two fingers too) zooms in and out where the pointer is, up to maxZoom times
// its own size; zoomed in, a drag moves it, and a double click fits it again. A new file starts fitted.
Item {
    id: root
    required property string source
    required property var pixels          // peek's [w, h] for a picture file; null for a rendered page or frame
    readonly property bool shown: source !== "" && image.status !== Image.Error
    readonly property real maxZoom: 4     // times the picture's own size
    readonly property real dpr: Screen.devicePixelRatio

    // Its own size: peek's, or a rendered page or frame's once loaded (pdftoppm/ffmpeg drew it small enough to load whole)
    readonly property var natural: pixels ? pixels
        : image.status === Image.Ready ? [image.implicitWidth, image.implicitHeight] : null
    readonly property real fit: natural ? Math.min(1, width / Math.max(1, natural[0]), height / Math.max(1, natural[1])) : 1
    readonly property real baseW: natural ? natural[0] * fit : width
    readonly property real baseH: natural ? natural[1] * fit : height

    // zoom is over the fitted size; ox, oy the picture's top-left in this item while zoomed in
    property real zoom: 1
    property real ox: 0
    property real oy: 0
    readonly property bool zoomed: zoom > 1.001
    onSourceChanged: reset()
    onWidthChanged: reset()
    onHeightChanged: reset()
    function reset() { zoom = 1; ox = (width - baseW) / 2; oy = (height - baseH) / 2; decode() }
    // A picture file is decoded only as large as it is shown (a 50-megapixel photo whole takes a lot of memory), and
    // whole once zoomed into, so it stays sharp; a rendered page or frame is small and loaded as it is. Set here, not
    // bound: a binding on sourceSize loops, as the Image changes it back to what it loaded
    function decode() {
        image.sourceSize = !pixels ? Qt.size(-1, -1)
            : zoomed ? Qt.size(Math.round(pixels[0] * wholeScale), Math.round(pixels[1] * wholeScale))
            : Qt.size(Math.ceil(baseW * dpr), Math.ceil(baseH * dpr))
    }
    // Whole, but no more than maxDecode on its longer side: a 100-megapixel scan would take 400 MB
    readonly property int maxDecode: 8192
    readonly property real wholeScale: pixels ? Math.min(1, maxDecode / Math.max(pixels[0], pixels[1])) : 1
    onPixelsChanged: reset()

    // A side smaller than the item stays centred on it; a larger one can't leave a gap at its edge
    function clampX(x, w) { return w <= width ? (width - w) / 2 : Math.min(0, Math.max(width - w, x)) }
    function clampY(y, h) { return h <= height ? (height - h) / 2 : Math.min(0, Math.max(height - h, y)) }
    function zoomAt(px, py, z) {
        if (!zoomed) { ox = (width - baseW) / 2; oy = (height - baseH) / 2 }   // from where the fitted one is
        const most = natural ? maxZoom / fit : maxZoom
        const nz = Math.max(1, Math.min(most, z))
        const k = nz / zoom
        const nx = px - (px - ox) * k, ny = py - (py - oy) * k
        const was = zoomed
        zoom = nz
        if (zoomed !== was) decode()
        ox = clampX(nx, baseW * nz); oy = clampY(ny, baseH * nz)
    }

    clip: true
    Image {
        id: image
        visible: root.shown
        x: root.zoomed ? root.ox : (root.width - width) / 2
        y: root.zoomed ? root.oy : (root.height - height) / 2
        width: Math.round(root.baseW * root.zoom)
        height: Math.round(root.baseH * root.zoom)
        fillMode: Image.PreserveAspectFit         // EXIF turns may swap peek's sides: never stretched
        asynchronous: true
        cache: false
        source: root.source
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        cursorShape: root.zoomed ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
        property real lastX: 0
        property real lastY: 0
        onWheel: w => root.zoomAt(w.x, w.y, root.zoom * Math.pow(1.0015, w.angleDelta.y || w.pixelDelta.y * 4))
        onPressed: m => { lastX = m.x; lastY = m.y }
        onPositionChanged: m => {
            if (!root.zoomed) return
            root.ox = root.clampX(root.ox + m.x - lastX, image.width)
            root.oy = root.clampY(root.oy + m.y - lastY, image.height)
            lastX = m.x; lastY = m.y
        }
        onDoubleClicked: root.reset()
    }
}
