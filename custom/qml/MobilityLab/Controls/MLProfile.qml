import QtQuick

import QGroundControl
import QGroundControl.Controls

// 고도 단면: the mission's altitude along its track (distance from start),
// terrain under each waypoint when QGC knows it, and where the aircraft is
// now. Flown legs grey, remaining legs cyan, the aircraft as a white marker.
Rectangle {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property real u:       MLTheme.u
    readonly property var  _mc:     globals.planMasterControllerFlyView ? globals.planMasterControllerFlyView.missionController : null
    readonly property var  _items:  _mc ? _mc.visualItems : null
    readonly property int  _cur:    _mc ? _mc.currentMissionIndex : -1

    function fv(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }

    // [{d, alt, terr, seq, idx}]
    readonly property var _pts: {
        var out = []
        if (!_items) return out
        var homeAmsl = _mc.plannedHomePosition && _mc.plannedHomePosition.isValid ? _mc.plannedHomePosition.altitude : NaN
        for (var i = 1; i < _items.count; i++) {
            var it = _items.get(i)
            if (!it || !it.specifiesCoordinate) continue
            var alt = (it.isSimpleItem && it.altitude) ? Number(it.altitude.rawValue) : NaN
            var terr = (!isNaN(homeAmsl) && !isNaN(it.terrainAltitude)) ? it.terrainAltitude - homeAmsl : NaN
            out.push({ d: it.distanceFromStart, alt: alt, terr: terr, seq: it.sequenceNumber, idx: i })
        }
        return out
    }
    readonly property real _minClear: {
        var m = NaN
        for (var i = 0; i < _pts.length; i++) {
            var p = _pts[i]
            if (!isNaN(p.alt) && !isNaN(p.terr)) m = isNaN(m) ? p.alt - p.terr : Math.min(m, p.alt - p.terr)
        }
        return m
    }

    color: MLTheme.panelSolid

    MLSection {
        id:     head
        width:  parent.width
        title:  qsTr("고도 단면 · 미션")
        detail: root._pts.length < 2 ? "" : (isNaN(root._minClear) ? qsTr("지형 정보 없음") : qsTr("경유점 지형 최소 이격 %1 m").arg(root._minClear.toFixed(0)))
        detailColor: !isNaN(root._minClear) && root._minClear < 20 ? MLTheme.caution : MLTheme.dim
    }

    MLText {
        visible:            root._pts.length < 2
        anchors.centerIn:   canvas
        text:               qsTr("미션이 올라가면 경로의 고도 단면이 보입니다")
        color:              MLTheme.faint
    }

    Canvas {
        id:                 canvas
        anchors.top:        head.bottom
        anchors.bottom:     parent.bottom
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.margins:    6 * u
        anchors.leftMargin: 8 * u
        anchors.rightMargin: 20 * u
        visible:            root._pts.length >= 2

        property real vehAlt:   root.vehicle ? root.fv(root.vehicle.altitudeRelative) : NaN
        property real vehNext:  root.vehicle ? root.fv(root.vehicle.distanceToNextWP) : NaN
        onVehAltChanged:        throttle.start()
        Timer { id: throttle; interval: 500; onTriggered: canvas.requestPaint() }
        onWidthChanged:         requestPaint()
        onHeightChanged:        requestPaint()
        Connections { target: root; function on_PtsChanged() { canvas.requestPaint() } function on_CurChanged() { canvas.requestPaint() } }

        onPaint: {
            var c = getContext("2d")
            c.reset()
            var P = root._pts
            if (P.length < 2) return
            var k = MLTheme.u
            var L = 40 * k, B = 18 * k, W = width, H = height
            var dMax = P[P.length - 1].d || 1
            var aMax = 0
            for (var i = 0; i < P.length; i++) aMax = Math.max(aMax, isNaN(P[i].alt) ? 0 : P[i].alt, isNaN(P[i].terr) ? 0 : P[i].terr)
            if (!isNaN(vehAlt)) aMax = Math.max(aMax, vehAlt)
            var step = aMax > 200 ? 100 : (aMax > 80 ? 40 : 20)
            aMax = Math.ceil((aMax * 1.15) / step) * step || step
            function X(d) { return L + (W - L) * d / dMax }
            function Y(a) { return (H - B) - (H - B - 4 * k) * a / aMax }

            c.font = (10 * k) + "px '" + MLTheme.mono + "'"
            c.textBaseline = "middle"
            for (var a = 0; a <= aMax; a += step) {
                c.strokeStyle = "#161C22"; c.lineWidth = 1
                c.beginPath(); c.moveTo(L, Y(a)); c.lineTo(W, Y(a)); c.stroke()
                c.fillStyle = "#56606A"; c.textAlign = "right"; c.fillText(a, L - 6 * k, Y(a))
            }

            // terrain under the waypoints
            var hasTerr = P.some(function(p) { return !isNaN(p.terr) })
            if (hasTerr) {
                c.beginPath(); c.moveTo(X(0), H - B)
                for (i = 0; i < P.length; i++) if (!isNaN(P[i].terr)) c.lineTo(X(P[i].d), Y(Math.max(0, P[i].terr)))
                c.lineTo(X(dMax), H - B); c.closePath()
                c.fillStyle = "#1A1F24"; c.fill(); c.strokeStyle = "#2D353D"; c.stroke()
            }

            // route: flown part grey, rest cyan
            var cur = root._cur
            for (i = 1; i < P.length; i++) {
                if (isNaN(P[i].alt) || isNaN(P[i - 1].alt)) continue
                c.strokeStyle = (cur > 0 && P[i].idx <= cur - 1) ? "#4A535C" : String(MLTheme.accent)
                c.lineWidth = 2 * k
                c.beginPath(); c.moveTo(X(P[i - 1].d), Y(P[i - 1].alt)); c.lineTo(X(P[i].d), Y(P[i].alt)); c.stroke()
            }
            c.fillStyle = "#7D848D"; c.textAlign = "center"; c.textBaseline = "alphabetic"
            for (i = 0; i < P.length; i++) {
                c.fillStyle = P[i].idx === cur ? String(MLTheme.accent) : "#7D848D"
                c.fillText(P[i].seq, X(P[i].d), H - 3 * k)
                c.beginPath(); c.arc(X(P[i].d), Y(isNaN(P[i].alt) ? 0 : P[i].alt), 2.5 * k, 0, 2 * Math.PI); c.fill()
            }

            // aircraft
            var target = null
            for (i = 0; i < P.length; i++) if (P[i].idx === cur) { target = P[i]; break }
            if (target && !isNaN(vehAlt)) {
                var dNow = Math.max(0, target.d - (isNaN(vehNext) ? 0 : vehNext))
                var vx = X(dNow), vy = Y(Math.max(0, vehAlt))
                c.strokeStyle = "#E6E4DE"; c.lineWidth = 1
                c.beginPath(); c.moveTo(vx, 2 * k); c.lineTo(vx, H - B); c.stroke()
                c.fillStyle = "#F2F1EE"
                c.beginPath(); c.moveTo(vx, vy - 3 * k); c.lineTo(vx - 7 * k, vy - 13 * k); c.lineTo(vx + 7 * k, vy - 13 * k); c.closePath(); c.fill()
            }
        }
    }
}
