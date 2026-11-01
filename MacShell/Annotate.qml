// Whiteboard: a blank canvas for sketching ideas, diagrams, and notes.
//   qs -c MacShell ipc call annotate toggle   Super+D   open / close the whiteboard
//   qs -c MacShell ipc call annotate clear    Super+C   clear the whiteboard
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "AnnoDraw.js" as D

Scope {
    id: root
    property var hub: null
    property var bar: hub ? hub.bar : null
    property var dock: hub ? hub.dock : null

    // ── look ──
    readonly property bool dark: bar ? (bar.effDark !== undefined ? bar.effDark : bar.darkMode) : true
    readonly property color tint: bar && bar.menuBorderColor ? bar.menuBorderColor : "#8A9AB5"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string boldFam: hub && hub.boldFontFamily ? hub.boldFontFamily : "Open Runde Semibold"
    function fontFor(weight) { return (weight >= Font.DemiBold && fam === "Open Runde") ? boldFam : fam; }
    readonly property color fg: dark ? "#F5F5F7" : "#1D1D1F"

    // ── pen state ──
    readonly property var palette: ["#1D1D1F", "#FFFFFF", "#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#0A84FF", "#BF5AF2"]
    readonly property var penWidths: [2.5, 5, 9]
    readonly property var eraseRadii: [12, 20, 32]
    property string tool: "pen"
    property int colorIdx: 2
    property int widthIdx: 1
    readonly property color penColor: palette[colorIdx]
    readonly property real strokeW: tool === "highlighter" ? penWidths[widthIdx] * 3.6 : penWidths[widthIdx]
    readonly property real eraseR: eraseRadii[widthIdx]

    // ── whiteboard window state ──
    property bool boardOpen: false
    function openBoard() { boardOpen = true; boardWin.openIt(); }
    function closeBoard() { boardOpen = false; boardWin.closeIt(); }
    function toggle() { if (boardOpen) closeBoard(); else openBoard(); }

    // ── the ink ──
    property var store: ({ "board": [] })
    signal inkChanged(string key)
    signal inkPainted(string key)

    function strokesOf(k) { return store[k] ? store[k] : []; }
    function inkCount(k) { return store[k] ? store[k].length : 0; }

    // ── undo / redo ──
    property var undoStack: []
    property var redoStack: []
    property int undoCount: 0
    property int redoCount: 0
    function pushOp(op) {
        undoStack.push(op);
        if (undoStack.length > 200) undoStack.shift();
        redoStack = [];
        undoCount = undoStack.length; redoCount = 0;
    }
    function undo() {
        if (undoStack.length === 0) return;
        var op = undoStack.pop();
        op.undo();
        redoStack.push(op);
        undoCount = undoStack.length; redoCount = redoStack.length;
    }
    function redo() {
        if (redoStack.length === 0) return;
        var op = redoStack.pop();
        op.redo();
        undoStack.push(op);
        undoCount = undoStack.length; redoCount = redoStack.length;
    }

    function commit(key, stroke) {
        if (!store[key]) store[key] = [];
        store[key].push(stroke);
        inkChanged(key);
        Qt.callLater(function() { root.inkChanged(key); });
        pushOp({
            undo: function () {
                var l = store[key] || [], i = l.indexOf(stroke);
                if (i >= 0) { l.splice(i, 1); inkChanged(key); }
            },
            redo: function () {
                if (!store[key]) store[key] = [];
                store[key].push(stroke);
                inkChanged(key);
            }
        });
    }

    function pushEraseOp(removed) {
        var rem = removed.slice();
        pushOp({
            undo: function () {
                for (var i = rem.length - 1; i >= 0; i--) {
                    var k = rem[i].key;
                    if (!store[k]) store[k] = [];
                    store[k].splice(rem[i].i, 0, rem[i].s);
                }
                inkChanged("board");
            },
            redo: function () {
                for (var i = 0; i < rem.length; i++) {
                    var l = store[rem[i].key];
                    if (l) l.splice(rem[i].i, 1);
                }
                inkChanged("board");
            }
        });
    }

    function eraseAt(gx, gy, r, mon, fixed) {
        var key = fixed ? fixed.key : "board";
        var list = store[key];
        if (!list || list.length === 0) return [];
        var w = fixed ? fixed.w : 1080, h = fixed ? fixed.h : 700;
        var removed = [], hit = false;
        for (var j = list.length - 1; j >= 0; j--) {
            if (D.nearStroke(list[j], gx, gy, r, w, h)) {
                removed.push({ key: key, i: j, s: list[j] });
                list.splice(j, 1);
                hit = true;
            }
        }
        if (hit) inkChanged(key);
        return removed;
    }

    function clearBoard() {
        var l = store["board"];
        if (!l || l.length === 0) return;
        var strokes = l.slice();
        store["board"] = [];
        inkChanged("board");
        pushOp({
            undo: function () {
                store["board"] = strokes.slice();
                inkChanged("board");
            },
            redo: function () {
                store["board"] = [];
                inkChanged("board");
            }
        });
    }

    IpcHandler {
        target: "annotate"
        function toggle(): void { root.toggle(); }
        function board(): void { root.openBoard(); }
        function pen(): void { root.toggle(); }
        function clear(): void { root.clearBoard(); }
        function clearPress(): void { root.clearBoard(); }
        function clearRelease(): void { }
        function clearAll(): void { root.clearBoard(); }
        function undo(): void { root.undo(); }
        function redo(): void { root.redo(); }
    }

    // ═════════════ the whiteboard: a window of its own ═════════════
    Window {
        id: boardWin
        title: "MacShell Whiteboard"
        width: 1080; height: 700
        minimumWidth: 640; minimumHeight: 420
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        property real appear: 0
        property bool gridOn: true
        property int floatTries: 0
        Behavior on appear { NumberAnimation { duration: root.boardOpen ? 420 : 220; easing.type: root.boardOpen ? Easing.OutBack : Easing.InCubic; easing.overshoot: 0.8 } }

        function openIt() { visible = true; appear = 1; floatTries = 0; floatTimer.restart(); raise(); requestActivate(); }
        function closeIt() { appear = 0; hideT.restart(); }
        Timer { id: hideT; interval: 230; onTriggered: if (!root.boardOpen) boardWin.visible = false }
        Timer {
            id: floatTimer
            interval: 60; repeat: true
            onTriggered: {
                var sel = 'window = "title:^(' + boardWin.title + ')$"';
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "22", ' + sel + ' })');
                if (boardWin.floatTries >= 2) {
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + boardWin.width + ', y = ' + boardWin.height + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                }
                if (++boardWin.floatTries >= 10) stop();
            }
        }
        Shortcut { sequences: ["Escape"]; onActivated: root.closeBoard() }
        Shortcut { sequences: ["Ctrl+Z"]; onActivated: root.undo() }
        Shortcut { sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]; onActivated: root.redo() }

        Item {
            id: boardRoot
            anchors.fill: parent
            opacity: Math.min(1, boardWin.appear * 1.8)
            scale: 0.95 + 0.05 * boardWin.appear
            transformOrigin: Item.Center

            Rectangle {
                id: sheet
                anchors.fill: parent
                radius: 22
                color: "#FAFAFC"
                antialiasing: true
            }
            // dot grid
            Canvas {
                id: grid
                anchors.fill: parent
                opacity: boardWin.gridOn ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d");
                    c.reset(); c.clearRect(0, 0, width, height);
                    c.fillStyle = "rgba(20,24,40,0.16)";
                    for (var y = 40; y < height - 10; y += 30) for (var x = 24; x < width - 10; x += 30) { c.beginPath(); c.arc(x, y, 1.2, 0, Math.PI * 2); c.fill(); }
                }
            }
            AnnoCanvas { x: 0; y: 0; width: pad.width; height: pad.height; anno: root; key: "board"; scale: 1 }
            AnnoPad {
                id: pad
                anchors.fill: parent
                anno: root
                fixedKey: "board"
                active: root.boardOpen
            }
            // title strip: drag to move, close dot
            Item {
                id: strip
                width: parent.width; height: 38
                MouseArea { anchors.fill: parent; onPressed: boardWin.startSystemMove() }
                Rectangle {
                    x: 16; y: 13; width: 13; height: 13; radius: 7; antialiasing: true
                    color: cm.containsMouse ? "#FF5F57" : "#FF6B63"
                    border.width: 0.5; border.color: Qt.rgba(0, 0, 0, 0.18)
                    scale: cm.pressed ? 0.85 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    AnnoIcon { anchors.centerIn: parent; kind: "close"; size: 9; color: Qt.rgba(0.3, 0, 0, 0.7); lw: 2.2; opacity: cm.containsMouse ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 140 } } }
                    MouseArea { id: cm; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; onClicked: root.closeBoard() }
                }
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Whiteboard")
                    color: Qt.rgba(0, 0, 0, 0.32)
                    font.family: root.fontFor(Font.DemiBold); font.pixelSize: 13; font.weight: Font.DemiBold
                }
            }
            AnnoToolbar {
                id: boardBar
                anno: root
                dark: true
                tint: root.tint
                fillA: 0.68
                shadow: true
                showGrid: true
                gridOn: boardWin.gridOn
                appear: boardWin.appear
                x: (parent.width - width) / 2
                y: parent.height - height - 22 + (1 - Math.min(1, boardWin.appear)) * 20
                onGridClicked: boardWin.gridOn = !boardWin.gridOn
                onDoneClicked: root.closeBoard()
            }
        }
    }
}
