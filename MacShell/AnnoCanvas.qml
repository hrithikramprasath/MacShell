import QtQuick
import "AnnoDraw.js" as D

// The committed ink of one anchor (a window, a workspace or the whiteboard). Sized like its anchor, so the strokes
// (stored 0..1) follow it when it moves or is resized.
Canvas {
    id: cv
    property var anno
    property string key: ""
    renderTarget: Canvas.FramebufferObject
    antialiasing: true
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.clearRect(0, 0, width, height);
        if (!anno || width < 2 || height < 2) return;
        var list = anno.strokesOf(key);
        for (var i = 0; i < list.length; i++) D.drawStroke(c, list[i], width, height);
    }
    onPainted: if (anno) anno.inkPainted(key)
    onWidthChanged: if (width >= 2 && height >= 2) requestPaint()
    onHeightChanged: if (width >= 2 && height >= 2) requestPaint()
    onVisibleChanged: if (visible && width >= 2 && height >= 2) requestPaint()
    onKeyChanged: if (key !== "" && width >= 2 && height >= 2) requestPaint()
    Component.onCompleted: if (width >= 2 && height >= 2) requestPaint()
    Connections {
        target: cv.anno
        function onInkChanged(k) { if (k === cv.key && cv.width >= 2 && cv.height >= 2) cv.requestPaint(); }
    }
}
