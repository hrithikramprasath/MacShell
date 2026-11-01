.pragma library

// Stroke drawing / hit-testing shared by the annotation overlay and the whiteboard.
// A stroke is { tool, color, w, pts: [x0, y0, x1, y1, ...], ws: [widthMultiplier per point] }.
// pts are multiplied by (W, H) when drawn: normalised 0..1 for stored ink (it follows its window), 1 / 1 for the live stroke (pixels).

function drawStroke(ctx, s, W, H) {
    var p = s.pts, n = p.length / 2;
    if (n < 1) return;
    var hi = s.tool === "highlighter";
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = s.color;
    ctx.fillStyle = s.color;
    ctx.globalAlpha = hi ? 0.4 : 1.0;
    var i, x, y;
    if (n === 1) {
        ctx.beginPath();
        ctx.arc(p[0] * W, p[1] * H, s.w * 0.5, 0, Math.PI * 2);
        ctx.fill();
    } else if (n === 2) {
        ctx.lineWidth = s.w;
        ctx.beginPath();
        ctx.moveTo(p[0] * W, p[1] * H);
        ctx.lineTo(p[2] * W, p[3] * H);
        ctx.stroke();
    } else if (hi) {
        // one path: a translucent ribbon must not darken where it overlaps itself
        ctx.lineWidth = s.w;
        ctx.beginPath();
        ctx.moveTo(p[0] * W, p[1] * H);
        for (i = 1; i < n - 1; i++) {
            x = (p[2 * i] + p[2 * i + 2]) * 0.5; y = (p[2 * i + 1] + p[2 * i + 3]) * 0.5;
            ctx.quadraticCurveTo(p[2 * i] * W, p[2 * i + 1] * H, x * W, y * H);
        }
        ctx.lineTo(p[2 * n - 2] * W, p[2 * n - 1] * H);
        ctx.stroke();
    } else {
        // pen: smooth curve through the midpoints, width varies with the pen speed (faster = thinner, like ink)
        var ws = s.ws, mx = p[0], my = p[1], nx, ny;
        for (i = 1; i < n - 1; i++) {
            nx = (p[2 * i] + p[2 * i + 2]) * 0.5; ny = (p[2 * i + 1] + p[2 * i + 3]) * 0.5;
            ctx.lineWidth = s.w * (ws && ws[i] ? ws[i] : 1);
            ctx.beginPath();
            ctx.moveTo(mx * W, my * H);
            ctx.quadraticCurveTo(p[2 * i] * W, p[2 * i + 1] * H, nx * W, ny * H);
            ctx.stroke();
            mx = nx; my = ny;
        }
        ctx.lineWidth = s.w * (ws && ws[n - 1] ? ws[n - 1] : 1);
        ctx.beginPath();
        ctx.moveTo(mx * W, my * H);
        ctx.lineTo(p[2 * n - 2] * W, p[2 * n - 1] * H);
        ctx.stroke();
    }
    ctx.restore();
}

function segDist(px, py, ax, ay, bx, by) {
    var dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy, t = 0;
    if (l2 > 0) { t = ((px - ax) * dx + (py - ay) * dy) / l2; t = t < 0 ? 0 : (t > 1 ? 1 : t); }
    var cx = ax + t * dx - px, cy = ay + t * dy - py;
    return Math.sqrt(cx * cx + cy * cy);
}

// is the point (lx, ly) (pixels, relative to the anchor's top-left) within r of the stroke drawn on a W x H anchor?
function nearStroke(s, lx, ly, r, W, H) {
    var p = s.pts, n = p.length / 2, reach = r + s.w * 0.5;
    if (n === 1) return Math.sqrt(Math.pow(p[0] * W - lx, 2) + Math.pow(p[1] * H - ly, 2)) <= reach;
    for (var i = 0; i < n - 1; i++)
        if (segDist(lx, ly, p[2 * i] * W, p[2 * i + 1] * H, p[2 * i + 2] * W, p[2 * i + 3] * H) <= reach) return true;
    return false;
}
