import QtQuick

import QGroundControl
import QGroundControl.Controls

// Compact primary flight display: attitude ball with pitch ladder and roll
// scale, speed tape (left), altitude tape (right), vertical speed bar and
// heading tape. Works for any vehicle type; fixed-wing/VTOL show airspeed.
Item {
    id: root

    property var vehicle

    readonly property bool _has:        !!vehicle
    readonly property bool _useAirspeed: _has && (vehicle.fixedWing || (vehicle.vtol && vehicle.vtolInFwdFlight))

    function _num(fact) {
        if (!fact) return 0
        var v = fact.rawValue
        return (v === undefined || isNaN(v)) ? 0 : v
    }

    readonly property real roll:    _has ? _num(vehicle.roll) : 0
    readonly property real pitch:   _has ? _num(vehicle.pitch) : 0
    readonly property real heading: _has ? _num(vehicle.heading) : 0
    readonly property real speed:   _has ? (_useAirspeed ? _num(vehicle.airSpeed) : _num(vehicle.groundSpeed)) : 0
    readonly property real alt:     _has ? _num(vehicle.altitudeRelative) : 0
    readonly property real vs:      _has ? _num(vehicle.climbRate) : 0

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 34
    implicitHeight: ScreenTools.defaultFontPixelHeight * 13

    Canvas {
        id:             canvas
        anchors.fill:   parent
        antialiasing:   true
        renderTarget:   Canvas.Image

        readonly property real _px: ScreenTools.defaultFontPixelHeight

        onPaint: {
            var c = getContext("2d")
            var W = width, H = height
            c.reset()
            c.clearRect(0, 0, W, H)

            var mono     = "bold " + Math.round(_px * 0.8) + "px '" + ScreenTools.fixedFontFamily + "'"
            var monoBig  = "bold " + Math.round(_px * 1.05) + "px '" + ScreenTools.fixedFontFamily + "'"
            var small    = Math.round(_px * 0.75) + "px '" + ScreenTools.fixedFontFamily + "'"
            var tw  = Math.round(_px * 3.4)     // tape width
            var vsw = Math.round(_px * 0.55)    // vertical speed bar
            var hh  = Math.round(_px * 2.0)     // heading tape height (top)
            var ib  = Math.round(_px * 1.3)     // info line (bottom)
            var x0 = tw + vsw * 0, x1 = W - tw - vsw, y0 = hh + _px * 0.3, y1 = H - ib
            var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
            var R  = Math.max(10, Math.min((x1 - x0) / 2 - _px * 0.9, (y1 - y0) / 2 - _px * 0.2))
            var ppd = R * 2 / 50               // pixels per degree of pitch
            var green = "#4ccf7c", dim = "#93a3a8", line = "#33475a"

            // ---- Attitude ball ----------------------------------------------
            c.save()
            c.beginPath(); c.arc(cx, cy, R, 0, Math.PI * 2); c.clip()
            c.translate(cx, cy)
            c.rotate(-root.roll * Math.PI / 180)
            c.translate(0, root.pitch * ppd)
            var sky = c.createLinearGradient(0, -R * 2, 0, 0)
            sky.addColorStop(0, "#0d3b6e"); sky.addColorStop(1, "#3f8fd6")
            c.fillStyle = sky; c.fillRect(-R * 3, -R * 4, R * 6, R * 4)
            var gnd = c.createLinearGradient(0, 0, 0, R * 2)
            gnd.addColorStop(0, "#8a5a30"); gnd.addColorStop(1, "#3e2714")
            c.fillStyle = gnd; c.fillRect(-R * 3, 0, R * 6, R * 4)
            c.strokeStyle = "white"; c.lineWidth = 2
            c.beginPath(); c.moveTo(-R * 3, 0); c.lineTo(R * 3, 0); c.stroke()
            c.lineWidth = 1.2; c.fillStyle = "white"; c.font = small; c.textBaseline = "middle"
            for (var p = -30; p <= 30; p += 5) {
                if (p === 0) continue
                var yy = -p * ppd
                var L = (p % 10 === 0) ? R * 0.32 : R * 0.14
                c.beginPath(); c.moveTo(-L, yy); c.lineTo(L, yy); c.stroke()
                if (p % 10 === 0) {
                    c.textAlign = "right"; c.fillText(Math.abs(p), -L - 4, yy)
                    c.textAlign = "left";  c.fillText(Math.abs(p), L + 4, yy)
                }
            }
            c.restore()

            // Bezel ring
            c.strokeStyle = line; c.lineWidth = Math.max(2, _px * 0.18)
            c.beginPath(); c.arc(cx, cy, R + c.lineWidth / 2, 0, Math.PI * 2); c.stroke()

            // Roll scale inside the top of the ball, pointer turns with roll
            c.save(); c.translate(cx, cy)
            var rr = R * 0.86
            c.strokeStyle = "white"; c.lineWidth = 1.4
            c.beginPath(); c.arc(0, 0, rr, -150 * Math.PI / 180, -30 * Math.PI / 180, false); c.stroke()
            var ticks = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]
            for (var i = 0; i < ticks.length; i++) {
                c.save(); c.rotate(ticks[i] * Math.PI / 180)
                var tl = (ticks[i] % 30 === 0) ? R * 0.1 : R * 0.055
                c.beginPath(); c.moveTo(0, -rr); c.lineTo(0, -rr - tl); c.stroke()
                c.restore()
            }
            c.fillStyle = "white"
            c.beginPath(); c.moveTo(0, -rr - 1); c.lineTo(-R * 0.05, -rr - R * 0.1); c.lineTo(R * 0.05, -rr - R * 0.1); c.closePath(); c.fill()
            c.rotate(-root.roll * Math.PI / 180)
            c.fillStyle = "#ffc61a"
            c.beginPath(); c.moveTo(0, -rr + 1); c.lineTo(-R * 0.06, -rr + R * 0.11); c.lineTo(R * 0.06, -rr + R * 0.11); c.closePath(); c.fill()
            c.restore()

            // Fixed aircraft symbol
            c.fillStyle = "#ffc61a"; c.strokeStyle = "black"; c.lineWidth = 1
            var wl = R * 0.55, wi = R * 0.2, wt = Math.max(3, R * 0.045)
            for (var s = -1; s <= 1; s += 2) {
                c.beginPath()
                c.moveTo(cx + s * wl, cy - wt / 2); c.lineTo(cx + s * wi, cy - wt / 2); c.lineTo(cx + s * wi, cy + R * 0.08)
                c.lineTo(cx + s * (wi + wt), cy + R * 0.08); c.lineTo(cx + s * (wi + wt), cy + wt / 2); c.lineTo(cx + s * wl, cy + wt / 2)
                c.closePath(); c.fill(); c.stroke()
            }
            c.beginPath(); c.moveTo(cx, cy - wt); c.lineTo(cx + wt * 1.6, cy + wt); c.lineTo(cx - wt * 1.6, cy + wt); c.closePath(); c.fill(); c.stroke()

            // ---- Tapes (plain scales with boxed readout) ---------------------
            function tape(x, w, v, ppu, step, labelEvery, rightSide, decimals) {
                c.save()
                c.beginPath(); c.rect(x, y0, w, y1 - y0); c.clip()
                c.strokeStyle = dim; c.fillStyle = "#c9d4d8"; c.lineWidth = 1; c.font = mono; c.textBaseline = "middle"
                var edge = rightSide ? x : x + w
                c.beginPath(); c.moveTo(edge, y0); c.lineTo(edge, y1); c.stroke()
                var span = (y1 - y0) / 2 / ppu
                var lo = Math.floor((v - span) / step) * step
                for (var u = lo; u <= v + span; u += step) {
                    var y = cy - (u - v) * ppu
                    var big = Math.round(u / step) % labelEvery === 0
                    c.beginPath()
                    if (rightSide) { c.moveTo(x, y); c.lineTo(x + (big ? 8 : 4), y) } else { c.moveTo(x + w, y); c.lineTo(x + w - (big ? 8 : 4), y) }
                    c.stroke()
                    if (big) { c.textAlign = rightSide ? "left" : "right"; c.fillText(Math.round(u), rightSide ? x + 11 : x + w - 11, y) }
                }
                c.restore()
                // readout box with pointer toward the ball
                var bh = _px * 1.55, bx = x + 1, bw = w - 2
                c.fillStyle = "#0a1a12"; c.strokeStyle = green; c.lineWidth = 1.5
                c.beginPath()
                if (rightSide) {
                    c.moveTo(bx + bw, cy - bh / 2); c.lineTo(bx + 6, cy - bh / 2); c.lineTo(bx, cy); c.lineTo(bx + 6, cy + bh / 2); c.lineTo(bx + bw, cy + bh / 2)
                } else {
                    c.moveTo(bx, cy - bh / 2); c.lineTo(bx + bw - 6, cy - bh / 2); c.lineTo(bx + bw, cy); c.lineTo(bx + bw - 6, cy + bh / 2); c.lineTo(bx, cy + bh / 2)
                }
                c.closePath(); c.fill(); c.stroke()
                c.fillStyle = "white"; c.font = monoBig; c.textAlign = "center"; c.textBaseline = "middle"
                c.fillText(v.toFixed(decimals), bx + bw / 2 + (rightSide ? 3 : -3), cy + 1)
            }
            tape(0, tw, root.speed, _px * 0.45, 1, 5, false, 1)
            tape(x1 + vsw, tw, root.alt, _px * 0.22, 5, 2, true, 0)

            // Vertical speed bar between the ball and the altitude tape
            var vx = x1 + 1
            c.fillStyle = "#18232c"; c.fillRect(vx, y0, vsw - 2, y1 - y0)
            var vh = Math.max(-1, Math.min(1, root.vs / 5)) * (y1 - y0) / 2
            c.fillStyle = Math.abs(root.vs) > 3 ? "#f5b331" : green
            c.fillRect(vx, cy, vsw - 2, -vh)

            // ---- Heading tape (top) -----------------------------------------
            c.save()
            c.beginPath(); c.rect(tw, 0, W - tw * 2, hh); c.clip()
            c.strokeStyle = dim; c.fillStyle = "#c9d4d8"; c.font = mono; c.textAlign = "center"; c.textBaseline = "top"; c.lineWidth = 1
            c.beginPath(); c.moveTo(0, hh - 1); c.lineTo(W, hh - 1); c.stroke()
            var hp = _px * 0.2, hs = W / 2 / hp
            for (var hd = Math.floor((root.heading - hs) / 5) * 5; hd <= root.heading + hs; hd += 5) {
                var hx = W / 2 + (hd - root.heading) * hp
                var n = ((hd % 360) + 360) % 360
                c.beginPath(); c.moveTo(hx, hh - 1); c.lineTo(hx, hh - (n % 10 === 0 ? 7 : 4)); c.stroke()
                if (n % 30 === 0) {
                    var lbl = n === 0 ? "N" : n === 90 ? "E" : n === 180 ? "S" : n === 270 ? "W" : ("00" + n).slice(-3)
                    c.fillText(lbl, hx, 1)
                }
            }
            c.restore()
            var hbw = _px * 3.4, hbh = hh * 0.62
            c.fillStyle = "#0a1a12"; c.strokeStyle = green; c.lineWidth = 1.5
            c.beginPath(); c.rect(W / 2 - hbw / 2, 0.5, hbw, hbh); c.fill(); c.stroke()
            c.beginPath(); c.moveTo(W / 2 - 5, hbh + 0.5); c.lineTo(W / 2, hbh + 6); c.lineTo(W / 2 + 5, hbh + 0.5); c.closePath(); c.fillStyle = green; c.fill()
            c.fillStyle = "white"; c.font = monoBig; c.textAlign = "center"; c.textBaseline = "middle"
            var hdg = Math.round(((root.heading % 360) + 360) % 360)
            c.fillText(("00" + hdg).slice(-3) + "°", W / 2, hbh / 2 + 1)

            // ---- Info line (bottom) ------------------------------------------
            c.font = small; c.textBaseline = "middle"; c.fillStyle = dim
            var iy = H - ib / 2
            c.textAlign = "left";   c.fillText(root._useAirspeed ? "IAS m/s" : "GS m/s", 2, iy)
            c.textAlign = "right";  c.fillText("ALT m", W - 2, iy)
            c.textAlign = "center"
            c.fillStyle = Math.abs(root.vs) > 3 ? "#f5b331" : "#e8eeeb"
            c.font = mono
            c.fillText("VS " + (root.vs >= 0 ? "+" : "") + root.vs.toFixed(1) + " m/s", W / 2, iy)

            if (!root._has) {
                c.fillStyle = "rgba(8,12,16,0.55)"; c.fillRect(0, 0, W, H)
            }
        }
    }

    QGCLabel {
        visible:            !root._has
        anchors.centerIn:   parent
        text:               qsTr("기체 연결 대기")
        color:              MLTheme.text
        font.bold:          true
    }

    Timer {
        interval:       66
        running:        root.visible
        repeat:         true
        onTriggered:    canvas.requestPaint()
    }
    Component.onCompleted: canvas.requestPaint()
}
