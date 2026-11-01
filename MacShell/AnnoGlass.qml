import QtQuick

// The annotation UI's glass surface: soft shadow, a tinted translucent fill (the compositor blurs what is behind it through the
// "macannotate-ui" layer rule), a specular highlight along the top and the same double-edge rim as the menu-bar popovers.
// Children go inside it. `appear` (0..1) drives the pop-in / pop-out.
Item {
    id: g
    property real radius: 24
    property bool dark: true
    property real fillA: 0.42                  // translucency of the glass (must stay above the layer rule's ignore_alpha to be blurred)
    property color tint: "#8A9AB5"
    property bool shadow: true
    property real appear: 1
    readonly property real sp: 44              // room around for the shadow (the window leaves this much margin)
    default property alias content: body.data

    // Dynamic dual-shadow cache for elements that morph between horizontal and vertical (e.g. AnnoToolbar):
    // Renders each shadow once and cross-fades them on the GPU, avoiding CPU Gaussian blur rasterization every frame.
    property bool dynamicShadow: false
    property bool verticalShadow: false
    property real hShadowW: 694
    property real hShadowH: 60
    property real hShadowR: 30
    property real vShadowW: 62
    property real vShadowH: 694
    property real vShadowR: 31

    opacity: Math.min(1, appear * 1.6)
    scale: 0.92 + 0.08 * appear
    transformOrigin: Item.Center

    Canvas {
        id: sh
        visible: g.shadow && !g.dynamicShadow
        x: -g.sp; y: -g.sp
        width: g.width + 2 * g.sp; height: g.height + 2 * g.sp
        property string sig: [g.width, g.height, g.radius].join("|")
        onSigChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d");
            c.reset();
            c.clearRect(0, 0, width, height);
            var x = g.sp, y = g.sp, w = g.width, h = g.height, r = Math.min(g.radius, h / 2, w / 2);
            function rr() {
                c.beginPath();
                c.moveTo(x + r, y); c.lineTo(x + w - r, y); c.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
                c.lineTo(x + w, y + h - r); c.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
                c.lineTo(x + r, y + h); c.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
                c.lineTo(x, y + r); c.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5); c.closePath();
            }
            c.shadowColor = "rgba(0,0,0,0.30)"; c.shadowBlur = 34; c.shadowOffsetX = 0; c.shadowOffsetY = 12;
            c.fillStyle = "#000000";
            rr(); c.fill();
            c.shadowColor = "transparent";
            c.globalCompositeOperation = "destination-out";     // keep only the part outside the glass
            rr(); c.fill();
        }
    }

    Canvas {
        id: shH
        visible: g.shadow && g.dynamicShadow && (!g.verticalShadow || opacity > 0.01)
        opacity: g.verticalShadow ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
        anchors.centerIn: parent
        width: g.hShadowW + 2 * g.sp; height: g.hShadowH + 2 * g.sp
        renderTarget: Canvas.FramebufferObject
        antialiasing: true
        Component.onCompleted: requestPaint()
        onPaint: {
            var c = getContext("2d");
            c.reset();
            c.clearRect(0, 0, width, height);
            var x = g.sp, y = g.sp, w = g.hShadowW, h = g.hShadowH, r = g.hShadowR;
            function rr() {
                c.beginPath();
                c.moveTo(x + r, y); c.lineTo(x + w - r, y); c.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
                c.lineTo(x + w, y + h - r); c.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
                c.lineTo(x + r, y + h); c.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
                c.lineTo(x, y + r); c.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5); c.closePath();
            }
            c.shadowColor = "rgba(0,0,0,0.30)"; c.shadowBlur = 34; c.shadowOffsetX = 0; c.shadowOffsetY = 12;
            c.fillStyle = "#000000";
            rr(); c.fill();
            c.shadowColor = "transparent";
            c.globalCompositeOperation = "destination-out";
            rr(); c.fill();
        }
    }

    Canvas {
        id: shV
        visible: g.shadow && g.dynamicShadow && (g.verticalShadow || opacity > 0.01)
        opacity: g.verticalShadow ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
        anchors.centerIn: parent
        width: g.vShadowW + 2 * g.sp; height: g.vShadowH + 2 * g.sp
        renderTarget: Canvas.FramebufferObject
        antialiasing: true
        Component.onCompleted: requestPaint()
        onPaint: {
            var c = getContext("2d");
            c.reset();
            c.clearRect(0, 0, width, height);
            var x = g.sp, y = g.sp, w = g.vShadowW, h = g.vShadowH, r = g.vShadowR;
            function rr() {
                c.beginPath();
                c.moveTo(x + r, y); c.lineTo(x + w - r, y); c.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
                c.lineTo(x + w, y + h - r); c.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
                c.lineTo(x + r, y + h); c.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
                c.lineTo(x, y + r); c.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5); c.closePath();
            }
            c.shadowColor = "rgba(0,0,0,0.30)"; c.shadowBlur = 34; c.shadowOffsetX = 0; c.shadowOffsetY = 12;
            c.fillStyle = "#000000";
            rr(); c.fill();
            c.shadowColor = "transparent";
            c.globalCompositeOperation = "destination-out";
            rr(); c.fill();
        }
    }

    // body of the glass
    Rectangle {
        anchors.fill: parent
        radius: g.radius
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: g.dark ? Qt.rgba(0.22, 0.23, 0.28, g.fillA + 0.08) : Qt.rgba(1, 1, 1, g.fillA + 0.24) }
            GradientStop { position: 1.0; color: g.dark ? Qt.rgba(0.07, 0.08, 0.11, g.fillA + 0.02) : Qt.rgba(0.90, 0.93, 0.98, g.fillA + 0.12) }
        }
    }
    // specular sheen along the top
    Rectangle {
        anchors.fill: parent; anchors.margins: 1
        radius: g.radius - 1
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, g.dark ? 0.20 : 0.55) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, g.dark ? 0.03 : 0.08) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
        opacity: 0.9
    }
    // inner glow edge + outer rim
    Rectangle {
        anchors.fill: parent; anchors.margins: 1
        radius: g.radius - 1; color: "transparent"; antialiasing: true
        border.width: 1; border.color: Qt.rgba(1, 1, 1, g.dark ? 0.07 : 0.35)
    }
    Rectangle {
        anchors.fill: parent
        radius: g.radius; color: "transparent"; antialiasing: true
        border.width: 1; border.color: g.dark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.80)
    }
    MenuBorder { anchors.fill: parent; cornerR: g.radius; dark: g.dark; tint: g.tint }

    Item { id: body; anchors.fill: parent }
}
