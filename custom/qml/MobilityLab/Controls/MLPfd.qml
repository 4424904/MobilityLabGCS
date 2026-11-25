import QtQuick

import QGroundControl
import QGroundControl.Controls

// Primary flight display, drawn in a fixed 460 × 400 design space and scaled
// to fit: rounded attitude window with pitch ladder and roll scale, speed tape
// (left), altitude tape and vertical-speed bar (right), heading tape (bottom).
// Target values (magenta) show as bugs on the tapes and above them.
Item {
    id: root

    property var  vehicle
    property real targetSpeed:      NaN
    property real targetAlt:        NaN
    property real targetHeading:    NaN

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

    implicitWidth:  460 * MLTheme.u
    implicitHeight: 400 * MLTheme.u

    Canvas {
        id:             canvas
        anchors.fill:   parent
        antialiasing:   true
        renderTarget:   Canvas.Image

        onPaint: {
            var c = getContext("2d")
            c.reset()
            c.clearRect(0, 0, width, height)
            var k = Math.min(width / 460, height / 400)
            c.translate((width - 460 * k) / 2, (height - 400 * k) / 2)
            c.scale(k, k)

            var mono = "'" + MLTheme.mono + "'"
            var sans = "'" + MLTheme.sans + "'"
            var cy = 162, cx = 222
            var white = "#F2F1EE", tick = "#9AA1A9", lbl = "#C8CDD2", dim = "#7D848D", tape = "#0D1115"
            var tgt = String(MLTheme.target), amber = String(MLTheme.caution), green = String(MLTheme.active)

            function rr(x, y, w, h, r) {
                c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r)
                c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath()
            }

            // ---- attitude -------------------------------------------------
            c.save()
            rr(72, 24, 300, 276, 10); c.clip()
            c.translate(cx, cy); c.rotate(-root.roll * Math.PI / 180); c.translate(0, root.pitch * 5)
            c.fillStyle = "#1F5C8F"; c.fillRect(-400, -600, 800, 600)
            c.fillStyle = "#5A3E26"; c.fillRect(-400, 0, 800, 600)
            c.strokeStyle = white; c.lineWidth = 1.5
            c.beginPath(); c.moveTo(-400, 0); c.lineTo(400, 0); c.stroke()
            c.lineWidth = 1.3; c.fillStyle = white; c.font = "11px " + mono; c.textBaseline = "middle"
            for (var p = -30; p <= 30; p += 5) {
                if (p === 0) continue
                var y = -p * 5, L = (p % 10 === 0) ? 40 : 18
                c.beginPath(); c.moveTo(-L, y); c.lineTo(L, y); c.stroke()
                if (p % 10 === 0) {
                    c.textAlign = "right"; c.fillText(Math.abs(p), -L - 5, y)
                    c.textAlign = "left";  c.fillText(Math.abs(p), L + 5, y)
                }
            }
            c.restore()
            c.strokeStyle = "#232931"; c.lineWidth = 1; rr(72.5, 24.5, 299, 275, 10); c.stroke()

            // roll scale
            c.save(); c.translate(cx, cy)
            c.strokeStyle = "#E6E4DE"; c.lineWidth = 1.3
            c.beginPath(); c.arc(0, 0, 120, -150 * Math.PI / 180, -30 * Math.PI / 180, false); c.stroke()
            var rt = [-60, -45, -30, -20, -10, 10, 20, 30, 45, 60]
            for (var i = 0; i < rt.length; i++) {
                var a = rt[i] * Math.PI / 180, tl = rt[i] % 30 === 0 ? 12 : 7
                c.beginPath(); c.moveTo(Math.sin(a) * 120, -Math.cos(a) * 120); c.lineTo(Math.sin(a) * (120 + tl), -Math.cos(a) * (120 + tl)); c.stroke()
            }
            c.fillStyle = "#E6E4DE"; c.beginPath(); c.moveTo(0, -120); c.lineTo(-6, -130); c.lineTo(6, -130); c.closePath(); c.fill()
            c.rotate(-root.roll * Math.PI / 180)
            c.fillStyle = amber; c.beginPath(); c.moveTo(0, -118); c.lineTo(-7, -106); c.lineTo(7, -106); c.closePath(); c.fill()
            c.restore()

            // aircraft symbol
            c.strokeStyle = amber; c.lineWidth = 3; c.lineJoin = "round"
            c.beginPath(); c.moveTo(150, cy); c.lineTo(198, cy); c.lineTo(198, cy + 10); c.stroke()
            c.beginPath(); c.moveTo(294, cy); c.lineTo(246, cy); c.lineTo(246, cy + 10); c.stroke()
            c.fillStyle = amber; c.fillRect(cx - 4, cy - 4, 8, 8)

            // ---- tapes ----------------------------------------------------
            function tapeTicks(x, w, val, ppu, step, big, right, min) {
                c.save(); c.beginPath(); c.rect(x, 24, w, 276); c.clip()
                c.fillStyle = tape; c.fillRect(x, 24, w, 276)
                c.strokeStyle = tick; c.lineWidth = 1.2; c.fillStyle = lbl; c.font = "12px " + mono; c.textBaseline = "middle"
                var span = 140 / ppu
                for (var v = Math.ceil((val - span) / step) * step; v <= val + span; v += step) {
                    if (v < min) continue
                    var yy = cy - (v - val) * ppu, isBig = Math.round(v / step) % big === 0, L = isBig ? 10 : 5
                    c.beginPath()
                    if (right) { c.moveTo(x, yy); c.lineTo(x + L, yy) } else { c.moveTo(x + w, yy); c.lineTo(x + w - L, yy) }
                    c.stroke()
                    if (isBig) {
                        c.textAlign = right ? "left" : "right"
                        c.fillText(Math.round(v), right ? x + 16 : x + w - 16, yy)
                    }
                }
                c.restore()
            }
            function bug(x, w, val, target, ppu, right) {
                if (isNaN(target)) return
                var yy = Math.max(30, Math.min(294, cy - (target - val) * ppu))
                c.fillStyle = tgt; c.beginPath()
                if (right) { c.moveTo(x, yy - 6); c.lineTo(x + 8, yy - 6); c.lineTo(x + 14, yy); c.lineTo(x + 8, yy + 6); c.lineTo(x, yy + 6) }
                else       { c.moveTo(x + w, yy - 6); c.lineTo(x + w - 8, yy - 6); c.lineTo(x + w - 14, yy); c.lineTo(x + w - 8, yy + 6); c.lineTo(x + w, yy + 6) }
                c.closePath(); c.fill()
            }
            function readout(xL, w, text, pointRight) {
                c.fillStyle = "#07090B"; c.strokeStyle = "#E6E4DE"; c.lineWidth = 1.5; c.beginPath()
                if (pointRight) { c.moveTo(xL, cy - 13); c.lineTo(xL + w, cy - 13); c.lineTo(xL + w + 10, cy); c.lineTo(xL + w, cy + 13); c.lineTo(xL, cy + 13) }
                else            { c.moveTo(xL + w, cy - 13); c.lineTo(xL, cy - 13); c.lineTo(xL - 10, cy); c.lineTo(xL, cy + 13); c.lineTo(xL + w, cy + 13) }
                c.closePath(); c.fill(); c.stroke()
                c.fillStyle = white; c.font = "16px " + mono; c.textAlign = "center"; c.textBaseline = "middle"
                c.fillText(text, xL + w / 2, cy + 1)
            }

            tapeTicks(8, 56, root.speed, 8, 1, 5, false, 0)
            bug(8, 56, root.speed, root.targetSpeed, 8, false)
            readout(6, 44, root.speed.toFixed(1), true)
            tapeTicks(380, 58, root.alt, 2.4, 5, 2, true, -1000)
            bug(380, 58, root.alt, root.targetAlt, 2.4, true)
            readout(400, 48, Math.round(root.alt).toString(), false)

            c.font = "12px " + mono; c.textAlign = "center"; c.textBaseline = "alphabetic"; c.fillStyle = tgt
            if (!isNaN(root.targetSpeed)) c.fillText(root.targetSpeed.toFixed(1), 36, 17)
            if (!isNaN(root.targetAlt))   c.fillText(Math.round(root.targetAlt), 409, 17)
            c.font = "11px " + sans; c.fillStyle = dim
            c.fillText(root._useAirspeed ? "IAS m/s" : "GS m/s", 36, 316)
            c.fillText("ALT m", 409, 316)

            // vertical speed
            c.strokeStyle = "#4A525B"; c.lineWidth = 1.2
            c.beginPath(); c.moveTo(452, 40); c.lineTo(452, 284); c.moveTo(452, cy); c.lineTo(458, cy)
            c.moveTo(452, cy - 60); c.lineTo(456, cy - 60); c.moveTo(452, cy + 60); c.lineTo(456, cy + 60); c.stroke()
            var vh = Math.max(-1, Math.min(1, root.vs / 5)) * 120
            c.fillStyle = Math.abs(root.vs) > 3 ? amber : green
            c.fillRect(450, vh >= 0 ? cy - vh : cy, 5, Math.max(2, Math.abs(vh)))

            // ---- heading tape --------------------------------------------
            c.save(); rr(72, 318, 300, 60, 6); c.fillStyle = tape; c.fill(); c.clip()
            c.strokeStyle = tick; c.lineWidth = 1.2; c.fillStyle = lbl; c.font = "12px " + mono; c.textAlign = "center"; c.textBaseline = "alphabetic"
            for (var h = Math.floor((root.heading - 40) / 5) * 5; h <= root.heading + 40; h += 5) {
                var hx = cx + (h - root.heading) * 4, n = ((h % 360) + 360) % 360
                c.beginPath(); c.moveTo(hx, 318); c.lineTo(hx, 318 + (n % 10 === 0 ? 10 : 5)); c.stroke()
                if (n % 10 === 0) {
                    c.fillStyle = n % 90 === 0 ? white : lbl
                    c.fillText(n === 0 ? "N" : n === 90 ? "E" : n === 180 ? "S" : n === 270 ? "W" : ("00" + n).slice(-3), hx, 370)
                }
            }
            c.restore()
            if (!isNaN(root.targetHeading)) {
                var d = ((root.targetHeading - root.heading + 540) % 360) - 180
                var bx = Math.max(80, Math.min(364, cx + d * 4))
                c.fillStyle = tgt; c.beginPath(); c.moveTo(bx - 6, 320); c.lineTo(bx + 6, 320); c.lineTo(bx, 330); c.closePath(); c.fill()
                if (Math.abs(d) > 35) {
                    c.font = "11px " + mono; c.textAlign = d > 0 ? "right" : "left"
                    c.fillText(("00" + Math.round((root.targetHeading + 360) % 360)).slice(-3), d > 0 ? bx - 10 : bx + 10, 331)
                }
            }
            c.fillStyle = "#07090B"; c.strokeStyle = "#E6E4DE"; c.lineWidth = 1.3
            c.beginPath(); c.moveTo(200, 320); c.lineTo(244, 320); c.lineTo(244, 338); c.lineTo(228, 338); c.lineTo(222, 344); c.lineTo(216, 338); c.lineTo(200, 338); c.closePath(); c.fill(); c.stroke()
            c.fillStyle = white; c.font = "13px " + mono; c.textAlign = "center"; c.textBaseline = "middle"
            c.fillText(("00" + Math.round(((root.heading % 360) + 360) % 360)).slice(-3), cx, 330)

            if (!root._has) { c.fillStyle = "rgba(7,9,11,0.6)"; c.fillRect(0, 0, 460, 400) }
        }
    }

    MLText {
        visible:            !root._has
        anchors.centerIn:   parent
        text:               qsTr("기체 연결 대기")
        font.weight:        Font.DemiBold
    }

    Timer {
        interval:       66
        running:        root.visible
        repeat:         true
        onTriggered:    canvas.requestPaint()
    }
    Component.onCompleted: canvas.requestPaint()
}
