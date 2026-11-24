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

            var mono     = "bold " + Math.round(_px * 0.85) + "px '" + ScreenTools.fixedFontFamily + "'"
            var monoBig  = "bold " + Math.round(_px * 1.0)  + "px '" + ScreenTools.fixedFontFamily + "'"
            var tw  = Math.round(_px * 3.6)     // tape width
            var vsw = Math.round(_px * 0.7)     // vertical speed bar
            var hh  = Math.round(_px * 1.9)     // heading tape height
            var x0 = tw, x1 = W - tw - vsw, y0 = 0, y1 = H - hh
            var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
            var ppd = (y1 - y0) / 40           // pixels per degree of pitch

            // ---- Attitude ---------------------------------------------------
            c.save()
            c.beginPath(); c.rect(x0, y0, x1 - x0, y1 - y0); c.clip()
            c.translate(cx, cy)
            c.rotate(-root.roll * Math.PI / 180)
            c.translate(0, root.pitch * ppd)

            var sky = c.createLinearGradient(0, -H * 1.5, 0, 0)
            sky.addColorStop(0, "#0f3a66"); sky.addColorStop(1, "#3c84c6")
            c.fillStyle = sky; c.fillRect(-W * 2, -H * 3, W * 4, H * 3)
            var gnd = c.createLinearGradient(0, 0, 0, H * 1.5)
            gnd.addColorStop(0, "#7a5230"); gnd.addColorStop(1, "#3b2614")
            c.fillStyle = gnd; c.fillRect(-W * 2, 0, W * 4, H * 3)

            c.strokeStyle = "white"; c.lineWidth = 2
            c.beginPath(); c.moveTo(-W * 2, 0); c.lineTo(W * 2, 0); c.stroke()

            c.lineWidth = 1.2; c.fillStyle = "white"; c.font = mono
            c.textBaseline = "middle"
            for (var p = -30; p <= 30; p += 5) {
                if (p === 0) continue
                var yy = -p * ppd
                var L = (p % 10 === 0) ? _px * 2.2 : _px * 1.0
                c.beginPath(); c.moveTo(-L, yy); c.lineTo(L, yy); c.stroke()
                if (p % 10 === 0) {
                    c.textAlign = "right"; c.fillText(Math.abs(p), -L - 4, yy)
                    c.textAlign = "left";  c.fillText(Math.abs(p), L + 4, yy)
                }
            }
            c.restore()

            // Roll scale and pointer
            var r = Math.min(x1 - x0, y1 - y0) * 0.43
            c.save(); c.translate(cx, cy)
            c.strokeStyle = "white"; c.lineWidth = 1.5
            c.beginPath(); c.arc(0, 0, r, -150 * Math.PI / 180, -30 * Math.PI / 180, false); c.stroke()
            var ticks = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]
            for (var i = 0; i < ticks.length; i++) {
                var a = ticks[i] * Math.PI / 180
                var tl = (ticks[i] % 30 === 0) ? _px * 0.7 : _px * 0.4
                c.save(); c.rotate(a)
                c.beginPath(); c.moveTo(0, -r); c.lineTo(0, -r - tl); c.stroke()
                c.restore()
            }
            c.rotate(-root.roll * Math.PI / 180)
            c.fillStyle = "white"
            c.beginPath(); c.moveTo(0, -r + 1); c.lineTo(-_px * 0.4, -r + _px * 0.7); c.lineTo(_px * 0.4, -r + _px * 0.7); c.closePath(); c.fill()
            c.restore()

            // Fixed aircraft symbol
            c.fillStyle = "#ffc61a"; c.strokeStyle = "black"; c.lineWidth = 1
            var wl = _px * 3.6, wi = _px * 1.3
            for (var s = -1; s <= 1; s += 2) {
                c.beginPath()
                c.moveTo(cx + s * wl, cy - 2); c.lineTo(cx + s * wi, cy - 2); c.lineTo(cx + s * wi, cy + _px * 0.5)
                c.lineTo(cx + s * (wi + _px * 0.3), cy + _px * 0.5); c.lineTo(cx + s * (wi + _px * 0.3), cy + 3); c.lineTo(cx + s * wl, cy + 3)
                c.closePath(); c.fill(); c.stroke()
            }
            c.fillRect(cx - 3, cy - 3, 6, 6); c.strokeRect(cx - 3, cy - 3, 6, 6)

            // ---- Tapes ------------------------------------------------------
            function tape(x, w, v, ppu, step, labelEvery, rightSide, decimals) {
                c.save()
                c.fillStyle = "rgba(8,12,14,0.82)"; c.fillRect(x, y0, w, y1 - y0)
                c.beginPath(); c.rect(x, y0, w, y1 - y0); c.clip()
                c.strokeStyle = "#cfd8da"; c.fillStyle = "#e6ece9"; c.lineWidth = 1; c.font = mono; c.textBaseline = "middle"
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
                var bh = _px * 1.5
                c.fillStyle = "black"; c.strokeStyle = "white"; c.lineWidth = 1.5
                c.beginPath(); c.rect(x + 2, cy - bh / 2, w - 4, bh); c.fill(); c.stroke()
                c.fillStyle = "white"; c.font = monoBig; c.textAlign = "center"; c.textBaseline = "middle"
                c.fillText(v.toFixed(decimals), x + w / 2, cy + 1)
            }
            tape(0, tw, root.speed, _px * 0.45, 1, 5, false, 1)
            tape(x1, tw, root.alt, _px * 0.22, 5, 2, true, 0)

            // Vertical speed bar
            var vx = W - vsw
            c.fillStyle = "rgba(8,12,14,0.82)"; c.fillRect(vx, y0, vsw, y1 - y0)
            var vh = Math.max(-1, Math.min(1, root.vs / 5)) * (y1 - y0) / 2
            c.fillStyle = Math.abs(root.vs) > 3 ? "#f5b331" : "#4ccf7c"
            c.fillRect(vx + 2, cy, vsw - 4, -vh)
            c.strokeStyle = "#cfd8da"; c.beginPath(); c.moveTo(vx, cy); c.lineTo(W, cy); c.stroke()

            // Heading tape
            c.save()
            c.fillStyle = "rgba(8,12,14,0.92)"; c.fillRect(0, y1, W, hh)
            c.beginPath(); c.rect(0, y1, W, hh); c.clip()
            c.strokeStyle = "#cfd8da"; c.fillStyle = "#e6ece9"; c.font = mono; c.textAlign = "center"; c.textBaseline = "top"
            var hp = _px * 0.22, hs = W / 2 / hp
            for (var hd = Math.floor((root.heading - hs) / 5) * 5; hd <= root.heading + hs; hd += 5) {
                var hx = W / 2 + (hd - root.heading) * hp
                var n = ((hd % 360) + 360) % 360
                c.beginPath(); c.moveTo(hx, y1); c.lineTo(hx, y1 + (n % 10 === 0 ? 7 : 4)); c.stroke()
                if (n % 30 === 0) {
                    var lbl = n === 0 ? "N" : n === 90 ? "E" : n === 180 ? "S" : n === 270 ? "W" : String(n / 10)
                    c.fillText(lbl, hx, y1 + 9)
                }
            }
            c.restore()
            var hbw = _px * 3.2
            c.fillStyle = "black"; c.strokeStyle = "white"; c.lineWidth = 1.5
            c.beginPath(); c.rect(W / 2 - hbw / 2, y1 + 2, hbw, hh - 4); c.fill(); c.stroke()
            c.fillStyle = "white"; c.font = monoBig; c.textAlign = "center"; c.textBaseline = "middle"
            var hdg = Math.round(((root.heading % 360) + 360) % 360)
            c.fillText(("00" + hdg).slice(-3) + "°", W / 2, y1 + hh / 2 + 1)

            if (!root._has) {
                c.fillStyle = "rgba(8,12,14,0.6)"; c.fillRect(0, 0, W, H)
            }
        }
    }

    // Unit labels at the bottom of each tape
    QGCLabel {
        x:                  ScreenTools.defaultFontPixelHeight * 0.3
        y:                  canvas.height - ScreenTools.defaultFontPixelHeight * 3.2
        text:               root._useAirspeed ? "IAS m/s" : "GS m/s"
        color:              MLTheme.dim
        font.pointSize:     ScreenTools.smallFontPointSize
    }
    QGCLabel {
        anchors.right:      parent.right
        anchors.rightMargin: ScreenTools.defaultFontPixelHeight * 1.0
        y:                  canvas.height - ScreenTools.defaultFontPixelHeight * 3.2
        text:               qsTr("고도 m")
        color:              MLTheme.dim
        font.pointSize:     ScreenTools.smallFontPointSize
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
