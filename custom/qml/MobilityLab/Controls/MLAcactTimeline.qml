import QtQuick
import QtQuick.Controls

// ACACT 이벤트 타임라인: the whole sequence from conflict prediction to avoidance and the
// return to the mission, on one time axis.
//   top     closest separation (guard's own value, 2 Hz) with D_SAFE / D_EMERG
//   lanes   one per vehicle: avoidance (red bar, takeover → release), return (amber), link loss,
//           operator takeover; pair lane: predicted conflict (▲) and cleared (△)
//   right   the events as text, newest first
Rectangle {
    id: root
    signal closeRequested()
    readonly property real u: MLTheme.u
    readonly property bool _has: typeof mlGuard !== "undefined"
    readonly property real dSafe:  _has && mlGuard.config.d_safe ? mlGuard.config.d_safe : 10
    readonly property real dEmerg: _has && mlGuard.config.d_emerg ? mlGuard.config.d_emerg : 5.5
    property real span: 180            // seconds shown; 0 = whole run
    property real tNow: 0
    Timer { interval: 500; running: root.visible; repeat: true; onTriggered: { root.tNow = root._has && mlGuard.running ? mlGuard.guardTime : root.lastT(); plot.requestPaint() } }
    // after the guard stops the run stays on screen up to its last record
    function lastT() {
        var t = 0
        if (MLState.acactSep.length) t = MLState.acactSep[MLState.acactSep.length - 1].t
        if (MLState.acactEvents.count) t = Math.max(t, MLState.acactEvents.get(MLState.acactEvents.count - 1).t)
        return t
    }

    color: MLTheme.glassStrong
    radius: MLTheme.panelRadius
    border.color: MLTheme.glassEdge

    function lanes() {
        var ids = []
        if (_has) for (var i = 0; i < mlGuard.drones.length; i++) ids.push(mlGuard.drones[i].id)
        for (var k = 0; k < MLState.acactEvents.count; k++) {
            var w = MLState.acactEvents.get(k).who
            if (/^D\d+$/.test(w) && ids.indexOf(w) < 0) ids.push(w)
        }
        ids.sort()
        return ids
    }

    // header
    Item {
        id: head
        width: parent.width; height: 40 * u
        Row {
            x: 14 * u; anchors.verticalCenter: parent.verticalCenter
            spacing: 12 * u
            MLText { text: qsTr("ACACT 이벤트 타임라인"); font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            Text { text: qsTr("가드 시간 %1").arg(MLTheme.duration(root.tNow)); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
            Row {
                spacing: 4 * u; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [ { s: 60, t: "1분" }, { s: 180, t: "3분" }, { s: 600, t: "10분" }, { s: 0, t: qsTr("전체") } ]
                    MLIconButton { size: 26 * root.u; label: modelData.t; checked: root.span === modelData.s; onClicked: { root.span = modelData.s; plot.requestPaint() } }
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 8 * u; anchors.verticalCenter: parent.verticalCenter
            spacing: 10 * u
            Repeater {
                model: [ { c: MLTheme.caution, t: qsTr("충돌 예측") }, { c: MLTheme.warning, t: qsTr("회피 기동") }, { c: MLTheme.active, t: qsTr("미션 복귀") }, { c: MLTheme.info, t: qsTr("운용자") } ]
                Row { spacing: 4 * root.u; anchors.verticalCenter: parent.verticalCenter
                    Rectangle { width: 10 * root.u; height: 10 * root.u; radius: 2 * root.u; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.t; color: MLTheme.label; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                }
            }
            MLIconButton { glyph: "✕"; tip: qsTr("닫기"); onClicked: root.closeRequested() }
        }
        Rectangle { anchors.bottom: parent.bottom; x: 10 * u; width: parent.width - 20 * u; height: 1; color: MLTheme.line }
    }

    Canvas {
        id: plot
        anchors.top: head.bottom; anchors.topMargin: 6 * u
        anchors.left: parent.left; anchors.leftMargin: 10 * u
        anchors.right: list.left; anchors.rightMargin: 10 * u
        anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * u
        renderStrategy: Canvas.Cooperative
        Connections { target: MLState; function onAcactSepRevChanged() { if (root.visible) plot.requestPaint() } }
        Connections { target: MLTheme; function onDayChanged() { plot.requestPaint() } }
        onPaint: {
            var c = getContext("2d"); c.reset()
            var k = root.u, W = width, H = height
            var L = 52 * k, R = W - 6 * k
            var t1 = Math.max(root.tNow, 1)
            var t0 = root.span > 0 ? Math.max(0, t1 - root.span) : (MLState.acactT0 > 0 ? MLState.acactT0 : 0)
            if (t1 - t0 < 10) t0 = t1 - 10
            function X(t) { return L + (t - t0) / (t1 - t0) * (R - L) }
            var font = (11 * k) + "px '" + MLTheme.mono + "'"
            c.font = font
            // separation chart
            var cH = Math.min(H * 0.42, 120 * k), cY0 = 4 * k, cY1 = cY0 + cH
            var dMax = root.dSafe * 3
            function Y(d) { return cY1 - Math.min(1, Math.max(0, d / dMax)) * cH }
            c.fillStyle = String(MLTheme.alpha(MLTheme.warning, 0.10)); c.fillRect(L, Y(root.dEmerg), R - L, cY1 - Y(root.dEmerg))
            c.fillStyle = String(MLTheme.alpha(MLTheme.caution, 0.08)); c.fillRect(L, Y(root.dSafe), R - L, Y(root.dEmerg) - Y(root.dSafe))
            c.strokeStyle = String(MLTheme.line); c.lineWidth = 1
            c.strokeRect(L + 0.5, cY0 + 0.5, R - L - 1, cH)
            c.fillStyle = String(MLTheme.dim); c.textAlign = "right"; c.textBaseline = "middle"
            c.fillText(root.dSafe.toFixed(0) + " m", L - 6 * k, Y(root.dSafe))
            c.fillText(root.dEmerg.toFixed(1), L - 6 * k, Y(root.dEmerg))
            c.fillText(dMax.toFixed(0), L - 6 * k, Y(dMax) + 6 * k)
            var S = MLState.acactSep
            c.lineWidth = 2
            for (var i = 1; i < S.length; i++) {
                if (S[i].t < t0) continue
                c.strokeStyle = String(MLTheme.riskColor(S[i].level))
                c.beginPath(); c.moveTo(X(S[i - 1].t), Y(S[i - 1].d)); c.lineTo(X(S[i].t), Y(S[i].d)); c.stroke()
            }
            c.textAlign = "left"; c.fillStyle = String(MLTheme.label)
            c.fillText(qsTr("최근접 이격"), L + 6 * k, cY0 + 9 * k)
            // lanes
            var ids = root.lanes()
            var laneTop = cY1 + 10 * k
            var laneH = Math.max(16 * k, Math.min(26 * k, (H - laneTop - 18 * k) / Math.max(1, ids.length + 1)))
            function laneY(i) { return laneTop + i * laneH }
            c.textAlign = "right"
            for (var li = 0; li < ids.length; li++) {
                var m = /^D(\d+)$/.exec(ids[li])
                c.fillStyle = String(MLTheme.vehicleColor(m ? Number(m[1]) : 1))
                c.fillText(ids[li], L - 6 * k, laneY(li) + laneH / 2)
                c.fillStyle = String(MLTheme.alpha(MLTheme.text, 0.04)); c.fillRect(L, laneY(li) + 2 * k, R - L, laneH - 4 * k)
            }
            c.fillStyle = String(MLTheme.dim); c.fillText(qsTr("쌍"), L - 6 * k, laneY(ids.length) + laneH / 2)
            // spans from events
            var open = ({}), ret = ({})
            var E = MLState.acactEvents
            function bar(id, ta, tb, col) {
                var li2 = ids.indexOf(id); if (li2 < 0) return
                var xa = Math.max(L, X(ta)), xb = Math.min(R, X(tb)); if (xb <= L || xa >= R) return
                c.fillStyle = col; c.fillRect(xa, laneY(li2) + 5 * k, Math.max(2 * k, xb - xa), laneH - 10 * k)
            }
            for (var e = 0; e < E.count; e++) {
                var ev = E.get(e)
                if (ev.kind === "takeover") open[ev.who] = { t: ev.t, col: String(MLTheme.warning) }
                else if (ev.kind === "operator") open[ev.who] = { t: ev.t, col: String(MLTheme.info) }
                else if ((ev.kind === "release" || ev.kind === "lost" || ev.kind === "stop") && open[ev.who]) {
                    bar(ev.who, open[ev.who].t, ev.t, open[ev.who].col); delete open[ev.who]
                    if (ev.kind === "release") bar(ev.who, ev.t, ev.t + 8, String(MLTheme.alpha(MLTheme.active, 0.6)))
                }
                if (ev.t < t0) continue
                var x = X(ev.t)
                if (ev.kind === "predict" || ev.kind === "clear") {
                    var y = laneY(ids.length) + laneH / 2
                    c.fillStyle = String(ev.kind === "clear" ? MLTheme.active : MLTheme.riskColor(ev.level))
                    c.beginPath(); c.moveTo(x, y - 6 * k); c.lineTo(x + 6 * k, y + 5 * k); c.lineTo(x - 6 * k, y + 5 * k); c.closePath()
                    if (ev.kind === "clear") { c.strokeStyle = c.fillStyle; c.lineWidth = 1.5; c.stroke() } else c.fill()
                    c.strokeStyle = String(MLTheme.alpha(MLTheme.caution, 0.35)); c.lineWidth = 1
                    if (ev.kind === "predict") { c.beginPath(); c.moveTo(x + 0.5, cY0); c.lineTo(x + 0.5, cY1); c.stroke() }
                } else if (ev.kind === "lost") {
                    var li3 = ids.indexOf(ev.who); if (li3 < 0) continue
                    c.strokeStyle = String(MLTheme.warning); c.lineWidth = 2
                    var yy = laneY(li3) + laneH / 2
                    c.beginPath(); c.moveTo(x - 5 * k, yy - 5 * k); c.lineTo(x + 5 * k, yy + 5 * k); c.moveTo(x + 5 * k, yy - 5 * k); c.lineTo(x - 5 * k, yy + 5 * k); c.stroke()
                } else if (ev.kind === "start" || ev.kind === "stop") {
                    c.strokeStyle = String(MLTheme.lineStrong); c.lineWidth = 1
                    c.beginPath(); c.moveTo(x + 0.5, cY0); c.lineTo(x + 0.5, laneY(ids.length + 1)); c.stroke()
                }
            }
            for (var id in open) bar(id, open[id].t, t1, open[id].col)
            // time axis
            var axY = laneY(ids.length + 1) + 2 * k
            c.fillStyle = String(MLTheme.dim); c.textAlign = "center"; c.textBaseline = "top"
            var step = (t1 - t0) > 900 ? 120 : ((t1 - t0) > 300 ? 60 : ((t1 - t0) > 90 ? 15 : 5))
            for (var tt = Math.ceil(t0 / step) * step; tt <= t1; tt += step) c.fillText(MLTheme.duration(tt), X(tt), axY)
        }
    }

    ListView {
        id: list
        anchors.top: head.bottom; anchors.topMargin: 6 * u
        anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * u
        anchors.right: parent.right; anchors.rightMargin: 10 * u
        width: Math.min(420 * u, parent.width * 0.36)
        clip: true
        model: MLState.acactEvents
        onCountChanged: positionViewAtEnd()
        ScrollBar.vertical: ScrollBar {}
        delegate: Row {
            width: list.width
            spacing: 8 * root.u
            Text { width: 48 * root.u; text: MLTheme.duration(model.t); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
            Rectangle {
                width: 6 * root.u; height: 6 * root.u; radius: 3 * root.u; anchors.verticalCenter: parent.verticalCenter
                color: model.kind === "takeover" || model.kind === "lost" ? MLTheme.warning : (model.kind === "predict" ? MLTheme.riskColor(model.level) : (model.kind === "release" || model.kind === "clear" ? MLTheme.active : (model.kind === "operator" ? MLTheme.info : MLTheme.dim)))
            }
            MLText { width: list.width - 70 * root.u; text: (/^D\d+$/.test(model.who) ? model.who + " · " : "") + model.text; font.pixelSize: MLTheme.fsLabel; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: MLTheme.text }
        }
    }
}
