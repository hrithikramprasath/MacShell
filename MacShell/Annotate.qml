//0.4.9
// Annotate: draw on your screen, or on a whiteboard.
//
//   qs -c MacShell ipc call annotate toggle        Super+D   pen on / off (asks: annotate the screen, or a whiteboard)
//   qs -c MacShell ipc call annotate pen | board   skip the question
//   qs -c MacShell ipc call annotate clearPress    Super+C   (press)   tap = clear this window, hold = clear everything
//   qs -c MacShell ipc call annotate clearRelease  Super+C   (release)
//
// Ink is anchored to the window it was drawn on (stored relative to the window, so it follows it when it moves, is resized, or when you
// switch workspace and come back). Ink drawn on the bare desktop belongs to that workspace. It lives on a layer-shell overlay, so
// screenshots (grim, the shell's own capture) include it. Keybinds: see config/hypr/hyprland.lua.
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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

    property bool penOn: false           // annotating the screen
    property bool pickerOpen: false
    property int pickSel: 0
    property bool boardOpen: false
    property string uiScreenName: ""
    readonly property var uiScreen: screenByName(uiScreenName)
    readonly property bool wantsGeo: penOn || keyModel.count > 0

    function screenByName(n) {
        var s = Quickshell.screens;
        for (var i = 0; i < s.length; i++) if (s[i].name === n) return s[i];
        return s.length > 0 ? s[0] : null;
    }
    function focusedMonitorName() {
        try { if (Hyprland.focusedMonitor) return Hyprland.focusedMonitor.name; } catch (e) { }
        return "";
    }

    Binding { target: root.hub; property: "annoWantsGeo"; value: root.wantsGeo; when: root.hub !== null }

    // ── the ink ──
    property var store: ({})             // anchor key -> [strokes]
    ListModel { id: keyModel }
    signal inkChanged(string key)
    signal inkPainted(string key)
    signal clearRequested(string key, int delay)

    function ensureKey(k) {
        for (var i = 0; i < keyModel.count; i++) if (keyModel.get(i).k === k) return;
        keyModel.append({ k: k });
    }
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
        ensureKey(key);
        if (!store[key]) store[key] = [];
        store[key].push(stroke);
        inkChanged(key);
        pushOp({
            undo: function () { var l = store[key] || [], i = l.indexOf(stroke); if (i >= 0) { l.splice(i, 1); inkChanged(key); } },
            redo: function () { ensureKey(key); if (!store[key]) store[key] = []; store[key].push(stroke); inkChanged(key); }
        });
    }
    function pushEraseOp(removed) {
        var rem = removed.slice();
        pushOp({
            undo: function () {                       // put the strokes back in reverse order, each at the place it was taken from
                for (var i = rem.length - 1; i >= 0; i--) { ensureKey(rem[i].key); if (!store[rem[i].key]) store[rem[i].key] = []; store[rem[i].key].splice(rem[i].i, 0, rem[i].s); }
                var seen = {};
                for (var j = 0; j < rem.length; j++) if (!seen[rem[j].key]) { seen[rem[j].key] = true; inkChanged(rem[j].key); }
            },
            redo: function () {
                var seen = {};
                for (var i = 0; i < rem.length; i++) { var l = store[rem[i].key]; if (l) l.splice(rem[i].i, 1); seen[rem[i].key] = true; }
                for (var k in seen) inkChanged(k);
            }
        });
    }
    // erase every stroke the eraser touches (in the anchors under the point); returns what was taken, for undo
    function eraseAt(gx, gy, r, mon, fixed) {
        var anchors = [], i, a;
        if (fixed) anchors.push(fixed);
        else {
            for (i = 0; i < keyModel.count; i++) {
                var k = keyModel.get(i).k, rc = rectFor(k, mon);
                if (rc && gx >= rc.x - r && gx <= rc.x + rc.w + r && gy >= rc.y - r && gy <= rc.y + rc.h + r)
                    anchors.push({ key: k, x: rc.x, y: rc.y, w: rc.w, h: rc.h });
            }
        }
        var removed = [];
        for (i = 0; i < anchors.length; i++) {
            a = anchors[i];
            var list = store[a.key], hit = false;
            if (!list) continue;
            for (var j = list.length - 1; j >= 0; j--) {
                if (D.nearStroke(list[j], gx - a.x, gy - a.y, r, a.w, a.h)) { removed.push({ key: a.key, i: j, s: list[j] }); list.splice(j, 1); hit = true; }
            }
            if (hit) inkChanged(a.key);
        }
        return removed;
    }

    // ── which window is where ──
    function norm(addr) { return String(addr).replace(/^0x/, ""); }
    function monByName(n) {
        var m = hub ? hub.monData : [];
        for (var i = 0; i < m.length; i++) if (m[i].name === n) return m[i];
        return null;
    }
    function monShowsWs(mon, id) {
        if (!mon) return false;
        if (mon.activeWorkspace && mon.activeWorkspace.id === id) return true;
        return !!(mon.specialWorkspace && mon.specialWorkspace.id !== 0 && mon.specialWorkspace.id === id);
    }
    function clientVisible(c, mon) {
        if (!mon || !c || !c.mapped || c.hidden || c.monitor !== mon.id) return false;
        if (c.title === "MacShell Whiteboard") return false;
        if (c.pinned) return true;
        return !!c.workspace && monShowsWs(mon, c.workspace.id);
    }
    function wsOf(mon) { return mon && mon.activeWorkspace ? mon.activeWorkspace.id : 1; }

    // the window (or, on bare desktop, the workspace) a stroke starting at (gx, gy) belongs to
    function resolveAnchor(gx, gy, monName) {
        var mon = monByName(monName), cl = hub ? hub.glassClients : [], best = null, bs = -1e9;
        for (var i = 0; i < cl.length; i++) {
            var c = cl[i];
            if (!clientVisible(c, mon) || !c.at || !c.size) continue;
            if (gx < c.at[0] || gx > c.at[0] + c.size[0] || gy < c.at[1] || gy > c.at[1] + c.size[1]) continue;
            var sc = (c.floating ? 1000 : 0) - (c.focusHistoryID !== undefined ? c.focusHistoryID : 0);
            if (sc > bs) { bs = sc; best = c; }
        }
        if (best) return { key: norm(best.address), x: best.at[0], y: best.at[1], w: Math.max(1, best.size[0]), h: Math.max(1, best.size[1]) };
        var s = screenByName(monName);
        return { key: "ws:" + wsOf(mon), x: s ? s.x : 0, y: s ? s.y : 0, w: s ? s.width : 1, h: s ? s.height : 1 };
    }
    // where an anchor is right now on this monitor (compositor coordinates), or null when it is not visible there
    function rectFor(key, monName) {
        var mon = monByName(monName);
        if (!mon) return null;
        var i;
        if (key.indexOf("ws:") === 0) {
            if (!monShowsWs(mon, parseInt(key.substring(3)))) return null;
            var s = screenByName(monName);
            return s ? { x: s.x, y: s.y, w: s.width, h: s.height } : null;
        }
        var cl = hub ? hub.glassClients : [];
        for (i = 0; i < cl.length; i++) {
            if (norm(cl[i].address) !== key) continue;
            if (!clientVisible(cl[i], mon) || !cl[i].at || !cl[i].size) return null;
            return { x: cl[i].at[0], y: cl[i].at[1], w: Math.max(1, cl[i].size[0]), h: Math.max(1, cl[i].size[1]) };
        }
        return null;
    }
    function screenHasInk(monName) {
        for (var i = 0; i < keyModel.count; i++) {
            var k = keyModel.get(i).k;
            if (inkCount(k) > 0 && rectFor(k, monName) !== null) return true;
        }
        return false;
    }
    function focusedKey() {
        var cl = hub ? hub.glassClients : [];
        for (var i = 0; i < cl.length; i++) if (cl[i].focusHistoryID === 0 && cl[i].mapped && !cl[i].hidden) return norm(cl[i].address);
        return "";
    }

    // forget the ink of windows that are gone
    property var missCount: ({})
    Timer {
        interval: 4000; repeat: true; running: keyModel.count > 0
        onTriggered: {
            var cl = root.hub ? root.hub.glassClients : [];
            if (cl.length === 0) return;
            var live = {}, i;
            for (i = 0; i < cl.length; i++) live[root.norm(cl[i].address)] = true;
            for (i = keyModel.count - 1; i >= 0; i--) {
                var k = keyModel.get(i).k;
                if (k.indexOf("ws:") === 0 || k === "board") continue;
                if (live[k]) { delete root.missCount[k]; continue; }
                root.missCount[k] = (root.missCount[k] || 0) + 1;
                if (root.missCount[k] >= 2) { keyModel.remove(i); delete root.store[k]; delete root.missCount[k]; }
            }
        }
    }

    // ── clearing ──
    Component { id: delayedCall; Timer { property var fn; running: true; onTriggered: { fn(); destroy(); } } }
    function requestClear(keys, stagger) {
        var items = [], i;
        for (i = 0; i < keys.length; i++) {
            var k = keys[i], l = store[k];
            if (!l || l.length === 0) continue;
            items.push({ key: k, strokes: l.slice() });
        }
        if (items.length === 0) return 0;
        for (i = 0; i < items.length; i++) {
            (function (it, delay) {
                clearRequested(it.key, delay);
                delayedCall.createObject(root, { interval: delay + 300, fn: function () { root.store[it.key] = []; root.inkChanged(it.key); } });
            })(items[i], i * stagger);
        }
        pushOp({
            undo: function () { for (var a = 0; a < items.length; a++) { root.ensureKey(items[a].key); root.store[items[a].key] = items[a].strokes.slice(); root.inkChanged(items[a].key); } },
            redo: function () { for (var b = 0; b < items.length; b++) { root.store[items[b].key] = []; root.inkChanged(items[b].key); } }
        });
        return items.length;
    }
    function clearCurrent() {
        var key = (boardOpen && boardWin.active) ? "board" : focusedKey();
        var target = "";
        if (key !== "" && inkCount(key) > 0) target = key;
        else {
            var fm = monByName(focusedMonitorName() !== "" ? focusedMonitorName() : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""));
            var ws = "ws:" + wsOf(fm);
            if (inkCount(ws) > 0) target = ws;
        }
        if (target === "") { toast(qsTr("Nothing to clear")); return; }
        requestClear([target], 0);
        toast(qsTr("Cleared"));
    }
    function clearAll() {
        var keys = [];
        for (var i = 0; i < keyModel.count; i++) keys.push(keyModel.get(i).k);
        if (requestClear(keys, 45) > 0) toast(qsTr("Cleared all"));
        else toast(qsTr("Nothing to clear"));
    }

    // Super+C: a tap clears the window, holding it (for 0.6 s, with a ring that fills up) clears everything
    property bool clearDown: false
    property real holdP: 0
    function clearPress() {
        if (clearDown) return;
        clearDown = true; holdP = 0;
        holdAnim.restart();
    }
    function clearRelease() {
        if (!clearDown) return;
        clearDown = false;
        holdAnim.stop();
        holdP = 0;
        clearCurrent();
    }
    function holdFire() { clearDown = false; holdP = 0; clearAll(); }
    SequentialAnimation {
        id: holdAnim
        PauseAnimation { duration: 190 }
        NumberAnimation { target: root; property: "holdP"; from: 0; to: 1; duration: 410; easing.type: Easing.InOutSine }
        ScriptAction { script: root.holdFire() }
    }

    // ── the little message under the screen: toast / hold ring ──
    property string hudMsg: ""
    property bool toastOn: false
    function toast(msg) {
        if (!uiScreenName || !penOn) uiScreenName = focusedMonitorName();
        hudMsg = msg; toastOn = true; toastT.restart();
    }
    Timer { id: toastT; interval: 1300; onTriggered: root.toastOn = false }
    readonly property bool hudShown: holdP > 0.01 || toastOn
    property real hudA: hudShown ? 1 : 0
    Behavior on hudA { NumberAnimation { duration: hudShown ? 300 : 260; easing.type: hudShown ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.3 } }

    // ── toggling ──
    function setPen(on) {
        if (on) { uiScreenName = focusedMonitorName(); }
        penOn = on;
    }
    function openPicker() {
        uiScreenName = focusedMonitorName();
        pickSel = 0; pickerOpen = true;
    }
    function closePicker() { pickerOpen = false; }
    function choose(i) {
        pickerOpen = false;
        if (i === 0) setPen(true); else openBoard();
    }
    function toggle() {
        if (boardOpen && boardWin.active) { closeBoard(); return; }
        if (penOn) { setPen(false); return; }
        if (pickerOpen) { closePicker(); return; }
        if (boardOpen) { closeBoard(); return; }
        openPicker();
    }
    function openBoard() { if (penOn) setPen(false); boardOpen = true; boardWin.openIt(); }
    function closeBoard() { boardOpen = false; boardWin.closeIt(); }

    IpcHandler {
        target: "annotate"
        function toggle(): void { root.toggle(); }
        function pen(): void { if (root.penOn) root.setPen(false); else { root.closePicker(); if (root.boardOpen) root.closeBoard(); root.setPen(true); } }
        function board(): void { if (root.boardOpen) root.closeBoard(); else { root.closePicker(); root.openBoard(); } }
        function clearPress(): void { root.clearPress(); }
        function clearRelease(): void { root.clearRelease(); }
        function clear(): void { root.clearCurrent(); }
        function clearAll(): void { root.clearAll(); }
        function undo(): void { root.undo(); }
        function redo(): void { root.redo(); }
    }

    // ═════════════ the ink: one click-through overlay per screen ═════════════
    Region { id: noInput }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: ink
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            visible: root.penOn || root.screenHasInk(modelData.name)
            mask: root.penOn ? null : noInput
            WlrLayershell.namespace: "macannotate"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Repeater {
                model: keyModel
                delegate: Item {
                    id: dl
                    required property string k
                    readonly property var r: root.rectFor(k, ink.modelData.name)
                    visible: r !== null && root.inkCount(k) > 0
                    x: r ? Math.round(r.x - ink.modelData.x) : 0
                    y: r ? Math.round(r.y - ink.modelData.y) : 0
                    width: r ? Math.round(r.w) : 1
                    height: r ? Math.round(r.h) : 1
                    clip: true
                    property real fade: 1
                    opacity: fade
                    AnnoCanvas { anchors.fill: parent; anno: root; key: dl.k; scale: 0.985 + 0.015 * dl.fade; transformOrigin: Item.Center }
                    SequentialAnimation {
                        id: fadeOut
                        PauseAnimation { id: fadePause; duration: 0 }
                        NumberAnimation { target: dl; property: "fade"; to: 0; duration: 280; easing.type: Easing.OutCubic }
                        PropertyAction { target: dl; property: "fade"; value: 1 }
                    }
                    Connections {
                        target: root
                        function onClearRequested(key, delay) { if (key === dl.k) { fadePause.duration = delay; fadeOut.restart(); } }
                    }
                }
            }
            AnnoPad {
                anchors.fill: parent
                anno: root
                originX: ink.modelData.x; originY: ink.modelData.y
                monName: ink.modelData.name
                active: root.penOn
            }
        }
    }

    // ═════════════ the pen palette (screen annotation) ═════════════
    PanelWindow {
        id: tbWin
        screen: root.uiScreen
        visible: root.penOn || tbAppear > 0.001
        property real tbAppear: root.penOn ? 1 : 0
        Behavior on tbAppear { NumberAnimation { duration: root.penOn ? 520 : 240; easing.type: root.penOn ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.05 } }
        anchors.bottom: true
        margins.bottom: 104
        implicitWidth: tbar.width + 2 * tbar.sp
        implicitHeight: tbar.height + 2 * tbar.sp
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: tbar }
        WlrLayershell.namespace: "macannotate-ui"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        AnnoToolbar {
            id: tbar
            anno: root
            fam: root.fam
            dark: root.dark
            tint: root.tint
            fillA: 0.40
            appear: tbWin.tbAppear
            x: tbar.sp; y: tbar.sp + (1 - Math.min(1, tbWin.tbAppear)) * 22
            onDoneClicked: root.setPen(false)
        }
    }

    // ═════════════ "Annotate" picker ═════════════
    PanelWindow {
        id: pickWin
        screen: root.uiScreen
        visible: root.pickerOpen || pickA > 0.001
        property real pickA: root.pickerOpen ? 1 : 0
        Behavior on pickA { NumberAnimation { duration: root.pickerOpen ? 560 : 240; easing.type: root.pickerOpen ? Easing.OutBack : Easing.InCubic; easing.overshoot: 0.9 } }
        implicitWidth: card.width + 2 * card.sp
        implicitHeight: card.height + 2 * card.sp
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: card }
        WlrLayershell.namespace: "macannotate-ui"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.pickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: if (visible) keyCatcher.forceActiveFocus()

        AnnoGlass {
            id: card
            x: sp; y: sp
            width: 556; height: 292
            radius: 34
            dark: root.dark
            tint: root.tint
            fillA: 0.40
            appear: pickWin.pickA

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) { root.pickSel = 0; e.accepted = true; }
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { root.pickSel = e.key === Qt.Key_Tab ? 1 - root.pickSel : 1; e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.choose(root.pickSel); e.accepted = true; }
                    else if (e.key === Qt.Key_1) { root.choose(0); e.accepted = true; }
                    else if (e.key === Qt.Key_2) { root.choose(1); e.accepted = true; }
                    else if (e.key === Qt.Key_Escape) { root.closePicker(); e.accepted = true; }
                }
            }

            Text {
                y: 24; width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Annotate")
                color: root.fg
                font.family: root.fontFor(Font.DemiBold); font.pixelSize: 19; font.weight: Font.DemiBold
            }

            Repeater {
                model: [
                    { name: qsTr("Screen"), hint: qsTr("Draw over your windows") },
                    { name: qsTr("Whiteboard"), hint: qsTr("A blank white canvas") }
                ]
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    x: 30 + index * 248; y: 66
                    width: 238; height: 168
                    readonly property bool sel: root.pickSel === index
                    scale: sel ? 1.035 : 1
                    Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Rectangle {
                        anchors.fill: parent; radius: 24; antialiasing: true
                        color: tile.sel ? Qt.rgba(1, 1, 1, root.dark ? 0.15 : 0.60) : Qt.rgba(1, 1, 1, root.dark ? 0.06 : 0.28)
                        border.width: tile.sel ? 1.6 : 1
                        border.color: tile.sel ? Qt.rgba(0.04, 0.52, 1, 0.95) : Qt.rgba(1, 1, 1, root.dark ? 0.14 : 0.5)
                        Behavior on color { ColorAnimation { duration: 240 } }
                        Behavior on border.color { ColorAnimation { duration: 240 } }
                    }
                    // illustration
                    Canvas {
                        x: (parent.width - 150) / 2; y: 16
                        width: 150; height: 92
                        property bool selNow: tile.sel
                        onSelNowChanged: requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            var c = getContext("2d");
                            c.reset(); c.clearRect(0, 0, width, height);
                            c.lineCap = "round"; c.lineJoin = "round";
                            function rr(x, y, w, h, r) {
                                c.beginPath(); c.moveTo(x + r, y); c.lineTo(x + w - r, y); c.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
                                c.lineTo(x + w, y + h - r); c.arc(x + w - r, y + h - r, r, 0, Math.PI / 2); c.lineTo(x + r, y + h);
                                c.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI); c.lineTo(x, y + r); c.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5); c.closePath();
                            }
                            if (tile.index === 0) {
                                rr(6, 12, 92, 62, 9); c.fillStyle = root.dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.06)"; c.fill();
                                c.strokeStyle = root.dark ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.35)"; c.lineWidth = 1.5; c.stroke();
                                c.beginPath(); c.moveTo(6, 27); c.lineTo(98, 27); c.stroke();
                                rr(52, 36, 88, 52, 9); c.fillStyle = root.dark ? "rgba(255,255,255,0.14)" : "rgba(255,255,255,0.7)"; c.fill(); c.stroke();
                                c.strokeStyle = "#FF453A"; c.lineWidth = 3.4;
                                c.beginPath(); c.moveTo(24, 66); c.bezierCurveTo(44, 30, 62, 84, 82, 52); c.bezierCurveTo(92, 36, 104, 44, 118, 30); c.stroke();
                            } else {
                                rr(10, 8, 130, 80, 11); c.fillStyle = "#FAFAFC"; c.fill();
                                c.strokeStyle = "rgba(0,0,0,0.18)"; c.lineWidth = 1.2; c.stroke();
                                c.fillStyle = "rgba(0,0,0,0.12)";
                                for (var gy = 0; gy < 4; gy++) for (var gx = 0; gx < 7; gx++) { c.beginPath(); c.arc(28 + gx * 16, 26 + gy * 17, 1.1, 0, Math.PI * 2); c.fill(); }
                                c.strokeStyle = "#0A84FF"; c.lineWidth = 3.4;
                                c.beginPath(); c.moveTo(30, 62); c.bezierCurveTo(46, 24, 62, 78, 80, 44); c.bezierCurveTo(90, 26, 104, 40, 120, 28); c.stroke();
                                c.strokeStyle = "#FF9F0A"; c.lineWidth = 3;
                                c.beginPath(); c.arc(44, 30, 8, 0, Math.PI * 2); c.stroke();
                            }
                        }
                    }
                    Text {
                        y: 114; width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.name
                        color: root.fg
                        font.family: root.fontFor(Font.DemiBold); font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        y: 138; width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.hint
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
                        font.family: root.fontFor(Font.Normal); font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onEntered: root.pickSel = tile.index
                        onClicked: root.choose(tile.index)
                    }
                }
            }

            Text {
                y: 252; width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "\u2190 \u2192   \u21B5   esc"
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.38)
                font.family: root.fontFor(Font.Normal); font.pixelSize: 12
            }
        }
    }

    // ═════════════ the hold ring / toast ═════════════
    PanelWindow {
        id: hudWin
        screen: root.uiScreen
        visible: root.hudA > 0.001
        anchors.bottom: true
        margins.bottom: 168
        implicitWidth: hud.width + 2 * hud.sp
        implicitHeight: hud.height + 2 * hud.sp
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { }
        WlrLayershell.namespace: "macannotate-ui"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        AnnoGlass {
            id: hud
            x: sp; y: sp + (1 - Math.min(1, root.hudA)) * 14
            width: hudRow.width + 40; height: 52; radius: 26
            dark: root.dark; tint: root.tint; fillA: 0.40
            appear: root.hudA
            Row {
                id: hudRow
                anchors.centerIn: parent
                spacing: 11
                Canvas {
                    id: ring
                    width: 24; height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    property real p: root.holdP
                    property bool holding: root.holdP > 0.01
                    onPChanged: requestPaint()
                    onHoldingChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d");
                        c.reset(); c.clearRect(0, 0, width, height);
                        c.lineCap = "round"; c.lineWidth = 2.6;
                        if (holding) {
                            c.strokeStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.2);
                            c.beginPath(); c.arc(12, 12, 9, 0, Math.PI * 2); c.stroke();
                            c.strokeStyle = "#FF453A";
                            c.beginPath(); c.arc(12, 12, 9, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); c.stroke();
                        } else {
                            c.strokeStyle = "#30D158"; c.lineWidth = 2.8; c.lineJoin = "round";
                            c.beginPath(); c.moveTo(5.5, 12.5); c.lineTo(10, 17); c.lineTo(18.5, 7.5); c.stroke();
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.holdP > 0.01 ? qsTr("Clear all") : root.hudMsg
                    color: root.fg
                    font.family: root.fontFor(Font.DemiBold); font.pixelSize: 14; font.weight: Font.DemiBold
                }
            }
        }
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
        Behavior on appear { NumberAnimation { duration: root.boardOpen ? 520 : 240; easing.type: root.boardOpen ? Easing.OutBack : Easing.InCubic; easing.overshoot: 0.8 } }

        function openIt() { visible = true; appear = 1; floatTries = 0; floatTimer.restart(); raise(); requestActivate(); }
        function closeIt() { appear = 0; hideT.restart(); }
        Timer { id: hideT; interval: 270; onTriggered: if (!root.boardOpen) boardWin.visible = false }
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
