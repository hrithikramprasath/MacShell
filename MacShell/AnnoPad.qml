import QtQuick
import "AnnoDraw.js" as D

// The drawing surface: takes the pointer, shows the live stroke and the brush cursor, and hands finished strokes to `anno`.
//   * fixedKey = "" (screen annotation): each stroke is anchored to the window (or workspace) under where it starts
//   * fixedKey = "board" (whiteboard): everything goes to that one anchor
Item {
    id: pad
    property var anno
    property string fixedKey: ""
    property real originX: 0            // where this item's top-left lies in the compositor's coordinates
    property real originY: 0
    property string monName: ""
    property bool active: true

    property bool pressed: false
    property bool hovering: false
    property real hx: -100
    property real hy: -100
    property var anchor: null
    property var livePts: []
    property var liveWs: []
    property string sTool: "pen"
    property string sColor: "#FF453A"
    property real sW: 4
    property real lastX: 0
    property real lastY: 0
    property real fx: 0
    property real fy: 0
    property real lastT: 0
    property real wm: 1
    property var erased: []
    property string pendingKey: ""

    function curAnchor(gx, gy) {
        if (pad.fixedKey !== "") return { key: pad.fixedKey, x: 0, y: 0, w: Math.max(1, pad.width), h: Math.max(1, pad.height) };
        return pad.anno.resolveAnchor(gx, gy, pad.monName);
    }
    function eraseHere(x, y) {
        var fixed = pad.fixedKey !== "" ? curAnchor(0, 0) : null;
        var gx = fixed ? x : pad.originX + x, gy = fixed ? y : pad.originY + y;
        var r = pad.anno.eraseAt(gx, gy, pad.anno.eraseR, pad.monName, fixed);
        if (r.length > 0) pad.erased = pad.erased.concat(r);
    }
    function down(x, y) {
        if (!pad.active || !pad.anno) return;
        pad.pressed = true;
        pad.hx = x; pad.hy = y;
        pad.sTool = pad.anno.tool;
        if (pad.sTool === "eraser") { pad.erased = []; eraseHere(x, y); return; }
        pad.sColor = pad.anno.penColor;
        pad.sW = pad.anno.strokeW;
        pad.anchor = curAnchor(pad.originX + x, pad.originY + y);
        pad.livePts = [x, y]; pad.liveWs = [1];
        pad.lastX = x; pad.lastY = y; pad.fx = x; pad.fy = y;
        pad.lastT = Date.now(); pad.wm = 1;
        pad.pendingKey = "";
        lc.requestPaint();
    }
    function move(x, y) {
        if (!pad.pressed) return;
        if (pad.sTool === "eraser") { eraseHere(x, y); return; }
        var dx = x - pad.lastX, dy = y - pad.lastY, d = Math.sqrt(dx * dx + dy * dy);
        if (d < 1.2) return;
        var now = Date.now(), dt = Math.max(1, now - pad.lastT);
        var target = pad.sTool === "highlighter" ? 1 : (1.18 - Math.min((d / dt) / 2.8, 1) * 0.62);
        pad.wm = pad.wm * 0.72 + target * 0.28;
        // a little stabiliser: the stroke trails the pointer slightly, which irons out hand jitter
        pad.fx += (x - pad.fx) * 0.62; pad.fy += (y - pad.fy) * 0.62;
        pad.livePts.push(pad.fx, pad.fy); pad.liveWs.push(pad.wm);
        pad.lastX = x; pad.lastY = y; pad.lastT = now;
        lc.requestPaint();
    }
    function up(x, y) {
        if (!pad.pressed) return;
        pad.pressed = false;
        if (pad.sTool === "eraser") {
            if (pad.erased.length > 0) pad.anno.pushEraseOp(pad.erased);
            pad.erased = [];
            return;
        }
        if (pad.livePts.length >= 4) { pad.livePts.push(x, y); pad.liveWs.push(pad.wm); }
        var a = pad.anchor, np = [], i;
        if (!a) return;
        for (i = 0; i < pad.livePts.length; i += 2) {
            np.push((pad.originX + pad.livePts[i] - a.x) / a.w, (pad.originY + pad.livePts[i + 1] - a.y) / a.h);
        }
        pad.pendingKey = a.key;
        pad.anno.commit(a.key, { tool: pad.sTool, color: pad.sColor, w: pad.sW, pts: np, ws: pad.liveWs.slice() });
        clearT.interval = 400;
        clearT.restart();
    }
    // keep the live stroke on screen until the committed canvas has painted it (no flicker)
    Timer { id: clearT; interval: 400; onTriggered: pad.dropLive() }
    function dropLive() { pad.livePts = []; pad.liveWs = []; lc.requestPaint(); }
    Connections {
        target: pad.anno
        function onInkPainted(k) {
            if (pad.pendingKey !== "" && k === pad.pendingKey && !pad.pressed) {
                pad.pendingKey = "";
                clearT.interval = 24;
                clearT.restart();
            }
        }
    }

    Canvas {
        id: lc
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        onPaint: {
            var c = getContext("2d");
            c.reset();
            c.clearRect(0, 0, width, height);
            if (pad.livePts.length >= 2)
                D.drawStroke(c, { tool: pad.sTool, color: pad.sColor, w: pad.sW, pts: pad.livePts, ws: pad.liveWs }, 1, 1);
        }
    }

    // brush cursor: a ring the size of the stroke (the eraser's reach), in the tool's colour
    Item {
        id: cur
        z: 5
        x: pad.hx; y: pad.hy
        visible: pad.active && pad.hovering
        readonly property bool er: pad.anno && pad.anno.tool === "eraser"
        property real d: er ? pad.anno.eraseR * 2 : Math.max(8, pad.anno ? pad.anno.strokeW : 6)
        readonly property color c: pad.anno ? pad.anno.penColor : "white"
        Behavior on d { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        scale: pad.pressed ? 0.82 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Rectangle {
            width: cur.d + 2; height: width; radius: width / 2; x: -width / 2; y: -height / 2
            color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.40); antialiasing: true
        }
        Rectangle {
            width: cur.d; height: width; radius: width / 2; x: -width / 2; y: -height / 2; antialiasing: true
            color: cur.er ? Qt.rgba(1, 1, 1, 0.10) : (pad.anno && pad.anno.tool === "highlighter" ? Qt.rgba(cur.c.r, cur.c.g, cur.c.b, 0.30) : cur.c)
            border.width: 1.5; border.color: cur.er ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.75)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: pad.active
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pad.active ? Qt.BlankCursor : Qt.ArrowCursor
        onPressed: m => pad.down(m.x, m.y)
        onPositionChanged: m => { pad.hx = m.x; pad.hy = m.y; pad.hovering = true; if (pressed) pad.move(m.x, m.y); }
        onReleased: m => pad.up(m.x, m.y)
        onCanceled: pad.up(pad.hx, pad.hy)
        onEntered: pad.hovering = true
        onExited: pad.hovering = false
    }
}
