import QtQuick

// The pen palette: tools, colours, stroke width, undo / redo. One pill, used under the screen annotation and inside the whiteboard.
AnnoGlass {
    id: tb
    property var anno
    property string fam: "Open Runde"
    property bool showGrid: false
    property bool vertical: false
    property bool grip: false
    property bool gridOn: false
    property string doneKind: "check"
    signal doneClicked()
    signal gridClicked()

    readonly property color fg: dark ? "#F5F5F7" : "#1D1D1F"
    readonly property var tools: ["pen", "highlighter", "eraser"]
    readonly property bool v: vertical
    height: v ? row.height + 30 : 60
    width: v ? 62 : row.width + 30
    radius: Math.min(width, height) / 2
    Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

    Grid {
        id: row
        anchors.centerIn: parent
        spacing: 0
        columns: tb.v ? 1 : 40
        // a quick dip while the bar turns, so the re-layout between horizontal and vertical reads as one motion
        opacity: 1
        property bool vs: tb.v
        onVsChanged: flip.restart()
        SequentialAnimation {
            id: flip
            NumberAnimation { target: row; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InCubic }
            PauseAnimation { duration: 90 }
            NumberAnimation { target: row; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        }

        // grip: shows where to grab the bar to move it
        Item {
            visible: tb.grip
            width: tb.v ? 46 : 22; height: tb.v ? 22 : 46
            Grid {
                anchors.centerIn: parent
                columns: tb.v ? 3 : 2; spacing: 3
                Repeater { model: 6; Rectangle { width: 3.5; height: 3.5; radius: 1.75; color: Qt.rgba(tb.fg.r, tb.fg.g, tb.fg.b, 0.34) } }
            }
        }

        // ── tools: a glass thumb slides under the selected one ──
        Item {
            width: tb.v ? 46 : 3 * 44; height: tb.v ? 3 * 44 : 46
            Rectangle {
                width: 44; height: 44; radius: 15; antialiasing: true
                readonly property int ti: Math.max(0, tb.tools.indexOf(tb.anno ? tb.anno.tool : "pen"))
                x: tb.v ? 1 : ti * 44
                y: tb.v ? ti * 44 : 1
                Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                color: Qt.rgba(1, 1, 1, tb.dark ? 0.17 : 0.55)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, tb.dark ? 0.24 : 0.8)
                Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
            }
            Repeater {
                model: tb.tools
                delegate: Item {
                    id: tbtn
                    required property string modelData
                    required property int index
                    x: tb.v ? 0 : index * 44; y: tb.v ? index * 44 : 0; width: tb.v ? 46 : 44; height: tb.v ? 44 : 46
                    readonly property bool sel: tb.anno && tb.anno.tool === modelData
                    AnnoIcon {
                        anchors.centerIn: parent
                        kind: tbtn.modelData; size: 23
                        color: tbtn.sel ? tb.fg : Qt.rgba(tb.fg.r, tb.fg.g, tb.fg.b, 0.62)
                        scale: tbm.pressed ? 0.86 : (tbm.containsMouse ? 1.12 : 1)
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                    }
                    MouseArea {
                        id: tbm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: m => { if (m.modifiers & Qt.MetaModifier) { m.accepted = false; return; } }
                        onClicked: m => { if (!(m.modifiers & Qt.MetaModifier)) tb.anno.tool = tbtn.modelData; }
                    }
                }
            }
        }

        Item { width: tb.v ? 46 : 22; height: tb.v ? 22 : 46; Rectangle { anchors.centerIn: parent; width: tb.v ? 26 : 1; height: tb.v ? 1 : 26; color: Qt.rgba(tb.fg.r, tb.fg.g, tb.fg.b, 0.16) } }

        // ── colours ──
        Item {
            width: tb.v ? 46 : 8 * 29; height: tb.v ? 8 * 29 : 46
            Repeater {
                model: tb.anno ? tb.anno.palette : []
                delegate: Item {
                    id: orb
                    required property string modelData
                    required property int index
                    x: tb.v ? 0 : index * 29; y: tb.v ? index * 29 : 0; width: tb.v ? 46 : 29; height: tb.v ? 29 : 46
                    readonly property bool sel: tb.anno && tb.anno.colorIdx === index
                    Rectangle {          // selection ring
                        anchors.centerIn: parent
                        width: 28; height: 28; radius: 14; color: "transparent"; antialiasing: true
                        border.width: 2; border.color: tb.fg
                        opacity: orb.sel ? 0.95 : 0
                        scale: orb.sel ? 1 : 0.7
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 20; height: 20; radius: 10; antialiasing: true
                        color: orb.modelData
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, orb.modelData === "#1D1D1F" ? 0.30 : 0.38)
                        scale: om.pressed ? 0.8 : (om.containsMouse ? 1.14 : (orb.sel ? 0.9 : 1))
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Rectangle {      // tiny highlight, so the orbs read as glass beads
                            x: 4; y: 3; width: 8; height: 5; radius: 3; rotation: -20
                            color: Qt.rgba(1, 1, 1, 0.35)
                        }
                    }
                    MouseArea {
                        id: om
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: m => { if (m.modifiers & Qt.MetaModifier) { m.accepted = false; return; } }
                        onClicked: m => { if (!(m.modifiers & Qt.MetaModifier)) tb.anno.colorIdx = orb.index; }
                    }
                }
            }
        }

        Item { width: tb.v ? 46 : 22; height: tb.v ? 22 : 46; Rectangle { anchors.centerIn: parent; width: tb.v ? 26 : 1; height: tb.v ? 1 : 26; color: Qt.rgba(tb.fg.r, tb.fg.g, tb.fg.b, 0.16) } }

        // ── stroke width ──
        Item {
            width: tb.v ? 46 : 3 * 30; height: tb.v ? 3 * 30 : 46
            Repeater {
                model: [5, 8, 12]
                delegate: Item {
                    id: wd
                    required property int modelData
                    required property int index
                    x: tb.v ? 0 : index * 30; y: tb.v ? index * 30 : 0; width: tb.v ? 46 : 30; height: tb.v ? 30 : 46
                    readonly property bool sel: tb.anno && tb.anno.widthIdx === index
                    Rectangle {
                        anchors.centerIn: parent
                        width: wd.modelData; height: width; radius: width / 2; antialiasing: true
                        color: tb.fg
                        opacity: wd.sel ? 0.95 : (wm.containsMouse ? 0.55 : 0.30)
                        scale: wm.pressed ? 0.8 : (wd.sel ? 1.2 : 1)
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    }
                    MouseArea {
                        id: wm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: m => { if (m.modifiers & Qt.MetaModifier) { m.accepted = false; return; } }
                        onClicked: m => { if (!(m.modifiers & Qt.MetaModifier)) tb.anno.widthIdx = wd.index; }
                    }
                }
            }
        }

        Item { width: tb.v ? 46 : 22; height: tb.v ? 22 : 46; Rectangle { anchors.centerIn: parent; width: tb.v ? 26 : 1; height: tb.v ? 1 : 26; color: Qt.rgba(tb.fg.r, tb.fg.g, tb.fg.b, 0.16) } }

        // ── undo / redo (grid, in the whiteboard) / done ──
        Repeater {
            model: tb.showGrid ? ["undo", "redo", "grid"] : ["undo", "redo"]
            delegate: Item {
                id: ab
                required property string modelData
                width: tb.v ? 46 : 38; height: tb.v ? 38 : 46
                readonly property bool isGrid: modelData === "grid"
                readonly property bool on: isGrid ? tb.gridOn : (modelData === "undo" ? tb.anno.undoCount > 0 : tb.anno.redoCount > 0)
                AnnoIcon {
                    anchors.centerIn: parent
                    kind: ab.modelData; size: 21
                    color: ab.isGrid && tb.gridOn ? "#0A84FF" : tb.fg
                    opacity: ab.on || ab.isGrid ? (am.containsMouse ? 1 : 0.8) : 0.28
                    scale: am.pressed ? 0.82 : (am.containsMouse && ab.on ? 1.12 : 1)
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                }
                MouseArea {
                    id: am; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: m => { if (m.modifiers & Qt.MetaModifier) { m.accepted = false; return; } }
                    onClicked: m => {
                        if (m.modifiers & Qt.MetaModifier) return;
                        if (ab.modelData === "undo") tb.anno.undo();
                        else if (ab.modelData === "redo") tb.anno.redo();
                        else tb.gridClicked();
                    }
                }
            }
        }

        Item {
            width: 46; height: 46
            Rectangle {
                anchors.centerIn: parent
                width: 34; height: 34; radius: 17; antialiasing: true
                color: dm.pressed ? Qt.rgba(0.04, 0.45, 0.9, 1) : Qt.rgba(0.04, 0.52, 1, dm.containsMouse ? 1 : 0.92)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
                scale: dm.pressed ? 0.9 : (dm.containsMouse ? 1.08 : 1)
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 140 } }
                AnnoIcon { anchors.centerIn: parent; kind: tb.doneKind; size: 18; color: "white"; lw: 1.9 }
            }
            MouseArea {
                id: dm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: m => { if (m.modifiers & Qt.MetaModifier) { m.accepted = false; return; } }
                onClicked: m => { if (!(m.modifiers & Qt.MetaModifier)) tb.doneClicked(); }
            }
        }
    }
}
