import QtQuick

// Small line icons for the annotation toolbar (24 x 24 grid, round caps, same stroke weight as the rest of the shell).
Canvas {
    id: ic
    property string kind: "pen"
    property color color: "white"
    property real size: 22
    property real lw: 1.7
    width: size; height: size
    onColorChanged: requestPaint()
    onKindChanged: requestPaint()
    onSizeChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.clearRect(0, 0, width, height);
        var s = width / 24;
        c.scale(s, s);
        c.strokeStyle = ic.color; c.fillStyle = ic.color;
        c.lineWidth = ic.lw; c.lineCap = "round"; c.lineJoin = "round";
        function line(a) { c.beginPath(); c.moveTo(a[0], a[1]); for (var i = 2; i < a.length; i += 2) c.lineTo(a[i], a[i + 1]); c.stroke(); }
        if (kind === "pen") {
            c.beginPath(); c.moveTo(4, 20); c.lineTo(5.2, 15.4); c.lineTo(16.4, 4.2); c.lineTo(19.8, 7.6); c.lineTo(8.6, 18.8); c.closePath(); c.stroke();
            line([14.2, 6.4, 17.6, 9.8]);
        } else if (kind === "highlighter") {
            c.beginPath(); c.moveTo(8.8, 13.2); c.lineTo(15.6, 6.4); c.lineTo(19.2, 10); c.lineTo(12.4, 16.8); c.closePath(); c.stroke();
            c.beginPath(); c.moveTo(8.8, 13.2); c.lineTo(6.2, 18.4); c.lineTo(10.2, 18.2); c.lineTo(12.4, 16.8); c.stroke();
            line([12.5, 21, 20.5, 21]);
        } else if (kind === "eraser") {
            c.beginPath(); c.moveTo(9.5, 19); c.lineTo(4.4, 13.9); c.lineTo(13.2, 5.1); c.lineTo(19.1, 11); c.lineTo(11.1, 19); c.closePath(); c.stroke();
            line([8.2, 9.9, 14.1, 15.8]);
            line([11.1, 19, 20.5, 19]);
        } else if (kind === "undo" || kind === "redo") {
            if (kind === "redo") { c.translate(24, 0); c.scale(-1, 1); }
            line([9, 6, 4.5, 10.5, 9, 15]);
            c.beginPath(); c.moveTo(4.8, 10.5); c.lineTo(14, 10.5);
            c.bezierCurveTo(17.8, 10.5, 19.8, 12.6, 19.8, 15.2);
            c.bezierCurveTo(19.8, 17.8, 17.8, 19.8, 14.2, 19.8); c.lineTo(11, 19.8); c.stroke();
        } else if (kind === "check") {
            c.lineWidth = ic.lw + 0.5;
            line([5, 12.6, 10, 17.4, 19, 7]);
        } else if (kind === "close") {
            line([6.5, 6.5, 17.5, 17.5]); line([17.5, 6.5, 6.5, 17.5]);
        } else if (kind === "grid") {
            for (var gy = 0; gy < 3; gy++) for (var gx = 0; gx < 3; gx++) {
                c.beginPath(); c.arc(6 + gx * 6, 6 + gy * 6, 1.45, 0, Math.PI * 2); c.fill();
            }
        }
    }
}
