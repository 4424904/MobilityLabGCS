import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls

// 비행 분석 · 리플레이 — post-flight view of ACACT guard logs (MLFlightAnalysis, context property mlAnalysis)
//
//   left    sessions (date · plan · SIM/FIELD · min separation · interventions)
//   centre  airspace replay seen from above (demo frame, F up), transport bar with intervention marks,
//           separation and altitude charts with the replay cursor (click to seek)
//   right   automatic verdict, pair and vehicle statistics, intervention history, events (click to seek)
//   header  PDF test report
Rectangle {
    id: root

    signal closeRequested()
    signal detachRequested()
    signal attachRequested()
    property bool detachable: false     // show "새 창" (open in its own window, e.g. on a second monitor)
    property bool attachable: false     // in its own window: show "주 화면으로"

    readonly property real u: MLTheme.u
    readonly property bool _ok: typeof mlAnalysis !== "undefined"
    readonly property bool _loaded: _ok && mlAnalysis.loaded
    property real   cursor: 0
    property bool   playing: false
    property real   speed: 4
    property var    state: []
    property bool   view3d: false
    property string chartKind: "alt"       // alt · spd · batt
    readonly property var ext: _loaded ? mlAnalysis.extent : ({})
    readonly property real dSafe: _loaded && mlAnalysis.verdict.dSafe ? mlAnalysis.verdict.dSafe : 10
    readonly property real dEmerg: _loaded && mlAnalysis.verdict.dEmerg ? mlAnalysis.verdict.dEmerg : 5.5
    readonly property real vSep: _loaded && mlAnalysis.verdict.vSep ? mlAnalysis.verdict.vSep : 4

    color:          MLTheme.glassStrong
    radius:         MLTheme.panelRadius
    border.color:   MLTheme.glassEdgeHi

    onVisibleChanged: if (visible && _ok) mlAnalysis.refresh()
    onCursorChanged: { if (_loaded) state = mlAnalysis.stateAt(cursor); live.requestPaint(); sepChart.requestPaint(); altChart.requestPaint() }
    Connections { target: MLTheme; function onDayChanged() { trackLayer.requestPaint(); live.requestPaint(); sepChart.requestPaint(); altChart.requestPaint() } }

    function fmt(t) { var s = Math.max(0, Math.floor(t)); return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2) }
    function m1(v) { return v === undefined || v === null ? "—" : Number(v).toFixed(1) + " m" }
    function seek(t) { cursor = Math.max(0, Math.min(mlAnalysis.duration, t)) }
    function open(stamp) {
        playing = false
        if (mlAnalysis.load(stamp)) { cursor = 0; state = mlAnalysis.stateAt(0); trackLayer.requestPaint(); live.requestPaint(); sepChart.requestPaint(); altChart.requestPaint() }
    }

    // a log loaded from elsewhere (tour, another window): draw it
    Connections {
        target: root._ok ? mlAnalysis : null
        function onLoadedChanged() {
            if (!mlAnalysis.loaded) return
            root.playing = false; root.cursor = 0; root.state = mlAnalysis.stateAt(0)
            trackLayer.requestPaint(); live.requestPaint(); sepChart.requestPaint(); altChart.requestPaint()
        }
    }

    Timer {
        interval: 50; repeat: true; running: root.playing && root._loaded
        onTriggered: { if (root.cursor >= mlAnalysis.duration) { root.playing = false; return } root.cursor = Math.min(mlAnalysis.duration, root.cursor + 0.05 * root.speed) }
    }

    FileDialog {
        id: pdfDialog
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("PDF (*.pdf)")]
        onAccepted: { var p = mlAnalysis.exportPdf(selectedFile); reportMsg.text = p !== "" ? qsTr("보고서 저장: %1").arg(p) : qsTr("※ 보고서를 저장하지 못했습니다") }
    }

    component Caption: MLText { color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.8 * MLTheme.u }
    component Btn: MLCommandButton { compact: true; implicitHeight: 32 * MLTheme.u; twoStep: false }
    component Card: Rectangle { radius: 6 * MLTheme.u; color: String(MLTheme.tile); border.color: MLTheme.line }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14 * u
        spacing: 10 * u

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12 * u
            Rectangle { width: 3 * u; height: 22 * u; color: MLTheme.brand }
            MLText { text: qsTr("비행 분석 · 리플레이"); font.pixelSize: MLTheme.fsValue; font.weight: Font.DemiBold; color: MLTheme.bright }
            MLText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall
                text: root._loaded ? (mlAnalysis.info.plan || qsTr("계획 정보 없음")) + " · " + root.fmt(mlAnalysis.duration) + " · " + mlAnalysis.stamp : qsTr("왼쪽에서 비행 기록을 고르세요")
            }
            MLText { id: reportMsg; color: MLTheme.label; font.pixelSize: MLTheme.fsLabel; Layout.maximumWidth: 420 * u; elide: Text.ElideMiddle }
            Btn { text: qsTr("PDF 보고서"); tone: "active"; available: root._loaded; disabledReason: qsTr("기록을 먼저 여세요")
                  onClicked: { pdfDialog.selectedFile = "file:///" + mlAnalysis.defaultReportPath().replace(/^\//, ""); pdfDialog.open() } }
            MLCommandButton {
                visible: root.detachable || root.attachable
                compact: true; twoStep: false; implicitHeight: 30 * MLTheme.u
                text: root.attachable ? qsTr("주 화면으로") : qsTr("새 창")
                onClicked: root.attachable ? root.attachRequested() : root.detachRequested()
            }
            Rectangle {
                Layout.preferredWidth: 30 * u; Layout.preferredHeight: 30 * u
                radius: 4 * u
                color: closeMouse.containsMouse ? MLTheme.panelRaised : "transparent"
                border.color: MLTheme.line
                Text { anchors.centerIn: parent; text: "✕"; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.playing = false; root.closeRequested() } }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: MLTheme.line }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12 * u

            // ---- sessions ----
            ColumnLayout {
                Layout.preferredWidth: 250 * u
                Layout.fillHeight: true
                spacing: 6 * u
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: qsTr("비행 기록"); Layout.fillWidth: true }
                    Btn { text: qsTr("새로고침"); onClicked: mlAnalysis.refresh() }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4 * u
                    model: root._ok ? mlAnalysis.sessions : []
                    ScrollBar.vertical: ScrollBar { width: 4 * u }
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width - 6 * u
                        height: sCol.implicitHeight + 14 * u
                        radius: 5 * u
                        readonly property bool cur: root._loaded && mlAnalysis.stamp === modelData.stamp
                        color: cur ? String(MLTheme.accentSoft) : (sMouse.containsMouse ? MLTheme.panelRaised : String(MLTheme.tile))
                        border.color: cur ? MLTheme.accent : MLTheme.line
                        Column {
                            id: sCol
                            x: 10 * u; y: 7 * u
                            width: parent.width - 20 * u
                            spacing: 3 * u
                            Row {
                                spacing: 8 * u
                                Text { text: modelData.date; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                                Rectangle {
                                    visible: !!modelData.opMode
                                    width: omt.implicitWidth + 8 * u; height: 14 * u; radius: 2 * u
                                    readonly property color c: modelData.opMode === "field" ? MLTheme.warning : (modelData.opMode === "demo" ? MLTheme.demo : MLTheme.accent)
                                    color: Qt.rgba(c.r, c.g, c.b, 0.14); border.color: c
                                    Text { id: omt; anchors.centerIn: parent; text: modelData.opMode === "field" ? "FIELD" : (modelData.opMode === "demo" ? "DEMO" : "SIM"); color: parent.c; font.family: MLTheme.mono; font.pixelSize: 10 * u }
                                }
                            }
                            MLText { width: parent.width; elide: Text.ElideRight; text: modelData.plan || modelData.vehicles || "—"; color: MLTheme.label; font.pixelSize: MLTheme.fsLabel }
                            Text {
                                visible: modelData.minSep !== undefined && modelData.minSep !== null
                                text: qsTr("최소 %1 · 개입 %2").arg(root.m1(modelData.minSep)).arg(modelData.takeovers)
                                color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel
                            }
                        }
                        MouseArea { id: sMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.open(modelData.stamp) }
                    }
                    MLText {
                        anchors.centerIn: parent
                        visible: parent.count === 0
                        width: parent.width - 20 * u
                        wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        color: MLTheme.faint; font.pixelSize: MLTheme.fsSmall
                        text: qsTr("가드를 한 번 실행하면 기록이 생깁니다\n%1").arg(root._ok ? mlAnalysis.logDir() : "")
                    }
                }
            }

            // ---- replay + charts ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8 * u

                Card {
                    id: airspace
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    // demo frame → pixels (F up, R right), equal scale
                    readonly property real span: root._loaded ? Math.max(root.ext.fMax - root.ext.fMin, root.ext.rMax - root.ext.rMin) : 100
                    readonly property real sc: Math.min(width, height) / span
                    readonly property real cx: width / 2 - (root._loaded ? (root.ext.rMin + root.ext.rMax) / 2 : 0) * sc
                    readonly property real cy: height / 2 + (root._loaded ? (root.ext.fMin + root.ext.fMax) / 2 : 0) * sc
                    function px(r) { return cx + r * sc }
                    function py(f) { return cy - f * sc }

                    Canvas {
                        id: trackLayer
                        anchors.fill: parent
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            if (!root._loaded) return
                            // grid
                            var g = airspace.span > 300 ? 50 : (airspace.span > 120 ? 20 : 10)
                            ctx.strokeStyle = String(MLTheme.line); ctx.lineWidth = 1
                            for (var f = Math.floor(root.ext.fMin / g) * g; f <= root.ext.fMax; f += g) { ctx.beginPath(); ctx.moveTo(0, airspace.py(f)); ctx.lineTo(width, airspace.py(f)); ctx.stroke() }
                            for (var r = Math.floor(root.ext.rMin / g) * g; r <= root.ext.rMax; r += g) { ctx.beginPath(); ctx.moveTo(airspace.px(r), 0); ctx.lineTo(airspace.px(r), height); ctx.stroke() }
                            var tr = mlAnalysis.tracks
                            for (var k = 0; k < tr.length; k++) {
                                var pts = tr[k].points
                                ctx.strokeStyle = MLTheme.vehicleColor(tr[k].sysid); ctx.globalAlpha = 0.35; ctx.lineWidth = 1.5
                                ctx.beginPath()
                                for (var i = 0; i < pts.length; i++) { var x = airspace.px(pts[i][2]), y = airspace.py(pts[i][1]); if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y) }
                                ctx.stroke()
                                // guard-flown parts
                                ctx.globalAlpha = 0.9; ctx.strokeStyle = MLTheme.warning; ctx.lineWidth = 2.5
                                for (i = 1; i < pts.length; i++) if (pts[i][4] && pts[i - 1][4]) { ctx.beginPath(); ctx.moveTo(airspace.px(pts[i - 1][2]), airspace.py(pts[i - 1][1])); ctx.lineTo(airspace.px(pts[i][2]), airspace.py(pts[i][1])); ctx.stroke() }
                                ctx.globalAlpha = 1
                            }
                            // scale bar
                            ctx.strokeStyle = MLTheme.label; ctx.lineWidth = 1.5
                            ctx.beginPath(); ctx.moveTo(14 * root.u, height - 14 * root.u); ctx.lineTo(14 * root.u + g * airspace.sc, height - 14 * root.u); ctx.stroke()
                            ctx.fillStyle = MLTheme.label; ctx.font = (11 * root.u) + "px '" + MLTheme.mono + "'"
                            ctx.fillText(g + " m", 14 * root.u, height - 20 * root.u)
                        }
                    }
                    Canvas {
                        id: live
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            if (!root._loaded) return
                            var st = root.state
                            // pair lines
                            for (var a = 0; a < st.length; a++) for (var b = a + 1; b < st.length; b++) {
                                var dh = Math.hypot(st[a].f - st[b].f, st[a].r - st[b].r), dz = Math.abs(st[a].alt - st[b].alt)
                                var same = dz < root.vSep && st[a].alt > 1 && st[b].alt > 1
                                var col = !same ? String(MLTheme.faint) : (dh < root.dEmerg ? MLTheme.warning : (dh < root.dSafe ? MLTheme.caution : "#5F6872"))
                                ctx.strokeStyle = col; ctx.lineWidth = same && dh < root.dSafe ? 2 : 1; ctx.setLineDash([4, 4])
                                ctx.beginPath(); ctx.moveTo(airspace.px(st[a].r), airspace.py(st[a].f)); ctx.lineTo(airspace.px(st[b].r), airspace.py(st[b].f)); ctx.stroke()
                                ctx.setLineDash([])
                                ctx.fillStyle = col; ctx.font = (11 * root.u) + "px '" + MLTheme.mono + "'"
                                ctx.fillText(dh.toFixed(1) + " m" + (same ? "" : "  Δz " + dz.toFixed(0)), (airspace.px(st[a].r) + airspace.px(st[b].r)) / 2 + 6, (airspace.py(st[a].f) + airspace.py(st[b].f)) / 2 - 6)
                            }
                            for (var k = 0; k < st.length; k++) {
                                var d = st[k], x = airspace.px(d.r), y = airspace.py(d.f), c = MLTheme.vehicleColor(d.sysid)
                                // safety ring: half of D_SAFE (two rings touching = guard threshold)
                                ctx.beginPath(); ctx.arc(x, y, root.dSafe / 2 * airspace.sc, 0, 2 * Math.PI)
                                ctx.fillStyle = d.own ? "rgba(255,90,82,0.16)" : "rgba(255,255,255,0.04)"; ctx.fill()
                                ctx.strokeStyle = d.own ? MLTheme.warning : c; ctx.lineWidth = d.own ? 2 : 1.2; ctx.globalAlpha = d.fresh ? 1 : 0.4; ctx.stroke()
                                // velocity (3 s)
                                ctx.strokeStyle = c; ctx.lineWidth = 2.5
                                ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + d.vr * 3 * airspace.sc, y - d.vf * 3 * airspace.sc); ctx.stroke()
                                ctx.beginPath(); ctx.arc(x, y, 5 * root.u, 0, 2 * Math.PI); ctx.fillStyle = c; ctx.fill()
                                ctx.globalAlpha = 1
                                ctx.fillStyle = c; ctx.font = "600 " + (12 * root.u) + "px '" + MLTheme.mono + "'"
                                ctx.fillText(d.id + "  " + Number(d.alt).toFixed(1) + " m", x + 10 * root.u, y - 10 * root.u)
                                ctx.fillStyle = d.own ? MLTheme.warning : (d.fresh ? MLTheme.dim : MLTheme.warning)
                                ctx.font = (10 * root.u) + "px '" + MLTheme.sans + "'"
                                ctx.fillText(d.own ? qsTr("ACACT 회피") : (d.fresh ? d.mode : qsTr("링크 두절")), x + 10 * root.u, y + 4 * root.u)
                            }
                        }
                    }
                    // HUD
                    Column {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12 * u
                        spacing: 2 * u
                        visible: root._loaded
                        Text { text: "T+" + root.fmt(root.cursor); color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: 22 * u; font.weight: Font.Medium }
                        MLText { text: qsTr("위에서 본 시연 좌표계 · 위쪽 = 전방 F"); color: MLTheme.faint; font.pixelSize: MLTheme.fsLabel }
                    }
                    // 3D replay (same log, heights to scale)
                    Loader {
                        anchors.fill: parent
                        active: root._loaded && root.view3d
                        sourceComponent: Component {
                            MLAcact3D {
                                detachable: false
                                replay: true
                                replayDrones: root.state
                                replayTracks: mlAnalysis.tracks
                                replayCursor: root.cursor
                                dSafeOverride: root.dSafe
                                onCloseRequested: root.view3d = false
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10 * u
                        visible: root._loaded && !root.view3d
                        MLIconButton { glyph: "◭"; label: qsTr("3D 리플레이"); size: 30 * root.u; onClicked: root.view3d = true }
                    }
                    MLText {
                        anchors.centerIn: parent
                        visible: !root._loaded
                        text: qsTr("비행 기록을 열면 여기서 다시 봅니다")
                        color: MLTheme.faint
                        font.pixelSize: MLTheme.fsBody
                    }
                }

                // transport
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * u
                    enabled: root._loaded
                    Btn { text: root.playing ? qsTr("일시정지") : qsTr("재생"); tone: "go"; selected: root.playing
                          onClicked: { if (!root.playing && root.cursor >= mlAnalysis.duration) root.cursor = 0; root.playing = !root.playing } }
                    Repeater {
                        model: [1, 4, 16]
                        Btn { required property int modelData; text: modelData + "×"; tone: "active"; selected: root.speed === modelData; onClicked: root.speed = modelData }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30 * u
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4 * u; radius: 2 * u; color: MLTheme.line }
                        Repeater {
                            model: root._loaded ? mlAnalysis.interventions : []
                            Rectangle {
                                required property var modelData
                                x: modelData.t0 / Math.max(1, mlAnalysis.duration) * parent.width
                                width: Math.max(2, modelData.dur / Math.max(1, mlAnalysis.duration) * parent.width)
                                anchors.verticalCenter: parent.verticalCenter
                                height: 10 * u; radius: 2 * u
                                color: MLTheme.warning; opacity: 0.75
                            }
                        }
                        // abnormal events: link loss / failsafe (red ▾), operator takeover (blue ▾)
                        Repeater {
                            model: root._loaded ? mlAnalysis.events.length : 0
                            Text {
                                readonly property var e: mlAnalysis.events[index]
                                readonly property bool bad: /두절|끊김|페일세이프|failsafe|lost|※/i.test(e.text)
                                readonly property bool op: /운용자|조종|모드 .* 전환|operator|pilot/i.test(e.text)
                                visible: bad || op
                                x: (e.t || 0) / Math.max(1, mlAnalysis.duration) * parent.width - width / 2
                                y: -4 * u
                                text: "▾"
                                color: bad ? MLTheme.warning : MLTheme.info
                                font.pixelSize: 14 * u
                            }
                        }
                        Rectangle {
                            x: root.cursor / Math.max(1, mlAnalysis.duration) * parent.width - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3 * u; height: 22 * u; radius: 1.5 * u; color: MLTheme.accent
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (mouse) => root.seek(mouse.x / width * mlAnalysis.duration)
                            onPositionChanged: (mouse) => { if (pressed) root.seek(mouse.x / width * mlAnalysis.duration) }
                        }
                    }
                    Text { text: root.fmt(root.cursor) + " / " + root.fmt(root._loaded ? mlAnalysis.duration : 0); color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                }

                // charts
                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 128 * u
                    Caption { x: 10 * u; y: 6 * u; text: qsTr("기체 간 거리 (같은 층 수평 / 아니면 3D) · 점선 D_SAFE·D_EMERG · 붉은 띠 = 가드 개입") }
                    Canvas {
                        id: sepChart
                        anchors.fill: parent; anchors.topMargin: 22 * u; anchors.margins: 8 * u
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset()
                            if (!root._loaded) return
                            var T = Math.max(1, mlAnalysis.duration), yMax = Math.max(30, root.dSafe * 3)
                            function X(t) { return t / T * width } function Y(v) { return height - Math.min(1, v / yMax) * height }
                            var iv = mlAnalysis.interventions
                            ctx.fillStyle = "rgba(255,90,82,0.13)"
                            for (var i = 0; i < iv.length; i++) ctx.fillRect(X(iv[i].t0), 0, Math.max(1, X(iv[i].t1) - X(iv[i].t0)), height)
                            ctx.setLineDash([3, 4]); ctx.lineWidth = 1
                            ctx.strokeStyle = MLTheme.caution; ctx.beginPath(); ctx.moveTo(0, Y(root.dSafe)); ctx.lineTo(width, Y(root.dSafe)); ctx.stroke()
                            ctx.strokeStyle = MLTheme.warning; ctx.beginPath(); ctx.moveTo(0, Y(root.dEmerg)); ctx.lineTo(width, Y(root.dEmerg)); ctx.stroke()
                            ctx.setLineDash([])
                            var pr = mlAnalysis.pairs
                            var pal = MLTheme.vehiclePalette
                            for (var k = 0; k < pr.length; k++) {
                                var s = pr[k].series, started = false
                                ctx.strokeStyle = pal[k % 6]; ctx.lineWidth = 1.5; ctx.beginPath()
                                for (i = 0; i < s.length; i++) {
                                    if (!s[i][3]) { started = false; continue }
                                    var v = Math.abs(s[i][2]) < root.vSep ? s[i][1] : Math.hypot(s[i][1], s[i][2])
                                    if (!started) { ctx.moveTo(X(s[i][0]), Y(v)); started = true } else ctx.lineTo(X(s[i][0]), Y(v))
                                }
                                ctx.stroke()
                                ctx.fillStyle = pal[k % 6]; ctx.font = (10 * root.u) + "px '" + MLTheme.mono + "'"
                                ctx.fillText(pr[k].a + "–" + pr[k].b, width - 60 * root.u - k * 56 * root.u, 10 * root.u)
                            }
                            ctx.strokeStyle = MLTheme.accent; ctx.lineWidth = 1.5
                            ctx.beginPath(); ctx.moveTo(X(root.cursor), 0); ctx.lineTo(X(root.cursor), height); ctx.stroke()
                        }
                        MouseArea { anchors.fill: parent; onClicked: (mouse) => root.seek(mouse.x / width * mlAnalysis.duration) }
                    }
                }
                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120 * u
                    Row {
                        x: 8 * u; y: 2 * u; spacing: 4 * u; z: 2
                        Repeater {
                            model: [ { k: "alt", t: qsTr("고도 (m)") }, { k: "spd", t: qsTr("속도 (m/s)") }, { k: "batt", t: qsTr("배터리 (%)") } ]
                            MLIconButton { size: 22 * root.u; label: modelData.t; checked: root.chartKind === modelData.k; onClicked: { root.chartKind = modelData.k; altChart.requestPaint() } }
                        }
                    }
                    Canvas {
                        id: altChart
                        anchors.fill: parent; anchors.topMargin: 22 * u; anchors.margins: 8 * u
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset()
                            if (!root._loaded) return
                            var col = root.chartKind === "spd" ? 5 : (root.chartKind === "batt" ? 6 : 3)
                            var tr = mlAnalysis.tracks
                            var yMax = root.chartKind === "batt" ? 100 : 1
                            if (root.chartKind !== "batt") for (var q = 0; q < tr.length; q++) for (var w = 0; w < tr[q].points.length; w++) { var vv = tr[q].points[w][col]; if (vv !== undefined && vv !== null) yMax = Math.max(yMax, vv * 1.1) }
                            var T = Math.max(1, mlAnalysis.duration)
                            function X(t) { return t / T * width } function Y(v) { return height - Math.min(1, v / yMax) * height }
                            ctx.fillStyle = String(MLTheme.dim); ctx.font = (10 * root.u) + "px '" + MLTheme.mono + "'"; ctx.textAlign = "right"
                            ctx.fillText(yMax.toFixed(0), width - 2, 10 * root.u)
                            var any = false
                            for (var k = 0; k < tr.length; k++) {
                                var p = tr[k].points, started = false
                                ctx.strokeStyle = MLTheme.vehicleColor(tr[k].sysid); ctx.lineWidth = 1.5; ctx.beginPath()
                                for (var i = 0; i < p.length; i++) {
                                    var y = p[i][col]
                                    if (y === undefined || y === null) { started = false; continue }
                                    any = true
                                    if (!started) { ctx.moveTo(X(p[i][0]), Y(y)); started = true } else ctx.lineTo(X(p[i][0]), Y(y))
                                }
                                ctx.stroke()
                            }
                            if (!any) { ctx.textAlign = "center"; ctx.fillStyle = String(MLTheme.faint); ctx.fillText(qsTr("이 기록에는 해당 데이터가 없습니다 (v1.0 이전 로그)"), width / 2, height / 2) }
                            ctx.strokeStyle = MLTheme.accent; ctx.lineWidth = 1.5
                            ctx.beginPath(); ctx.moveTo(X(root.cursor), 0); ctx.lineTo(X(root.cursor), height); ctx.stroke()
                        }
                        MouseArea { anchors.fill: parent; onClicked: (mouse) => root.seek(mouse.x / width * mlAnalysis.duration) }
                    }
                }
            }

            // ---- results ----
            Flickable {
                Layout.preferredWidth: 320 * u
                Layout.fillHeight: true
                clip: true
                contentHeight: rCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { width: 4 * u }
                ColumnLayout {
                    id: rCol
                    width: parent.width - 8 * u
                    spacing: 8 * u
                    visible: root._loaded

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: vCol.implicitHeight + 20 * u
                        radius: 6 * u
                        readonly property bool pass: root._loaded && mlAnalysis.verdict.pass
                        color: pass ? String(MLTheme.alpha(MLTheme.active, 0.15)) : String(MLTheme.warningFill)
                        border.color: pass ? MLTheme.active : MLTheme.warning
                        Column {
                            id: vCol
                            x: 12 * u; y: 10 * u
                            width: parent.width - 24 * u
                            spacing: 4 * u
                            MLText { text: parent.parent.pass ? qsTr("이격 기준 충족") : qsTr("기준 미충족"); color: parent.parent.pass ? MLTheme.active : MLTheme.warning; font.pixelSize: MLTheme.fsValue; font.weight: Font.DemiBold }
                            MLText {
                                width: parent.width; wrapMode: Text.WordWrap
                                color: MLTheme.label; font.pixelSize: MLTheme.fsSmall
                                text: root._loaded ? (mlAnalysis.verdict.reasons.length ? mlAnalysis.verdict.reasons.join(" · ")
                                                      : qsTr("같은 층 최소 수평 이격 %1 (긴급 %2 m 이상) · 자동 판정, 시험 책임자 검토 필요").arg(root.m1(mlAnalysis.verdict.minSame)).arg(root.dEmerg)) : ""
                            }
                        }
                    }

                    Caption { text: qsTr("기체 간 이격") }
                    Repeater {
                        model: root._loaded ? mlAnalysis.pairs : []
                        Card {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: pGrid.implicitHeight + 16 * u
                            GridLayout {
                                id: pGrid
                                x: 10 * u; y: 8 * u
                                width: parent.width - 20 * u
                                columns: 2; rowSpacing: 2 * u; columnSpacing: 8 * u
                                Text { text: modelData.a + " – " + modelData.b; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; Layout.columnSpan: 2 }
                                MLText { text: qsTr("같은 층 최소"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                Text { text: root.m1(modelData.minSame) + (modelData.tMin >= 0 ? "  @" + root.fmt(modelData.tMin) : ""); color: modelData.minSame !== null && modelData.minSame < root.dEmerg ? MLTheme.warning : MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
                                       MouseArea { anchors.fill: parent; enabled: modelData.tMin >= 0; cursorShape: Qt.PointingHandCursor; onClicked: root.seek(modelData.tMin - 3) } }
                                MLText { text: qsTr("3D 최소"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                Text { text: root.m1(modelData.min3d); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                                MLText { text: qsTr("D_SAFE / D_EMERG 미만"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                Text { text: Number(modelData.belowSafe).toFixed(1) + " s / " + Number(modelData.belowEmerg).toFixed(1) + " s"; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                            }
                        }
                    }

                    Caption { text: qsTr("기체") }
                    Repeater {
                        model: root._loaded ? mlAnalysis.vehicles : []
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8 * u
                            Rectangle { Layout.preferredWidth: 3 * u; Layout.preferredHeight: 16 * u; color: MLTheme.vehicleColor(modelData.sysid) }
                            Text { text: modelData.id; color: MLTheme.vehicleColor(modelData.sysid); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; Layout.preferredWidth: 26 * u }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel
                                   text: qsTr("비행 %1 · 개입 %2회 %3 s · 링크 공백 %4 s").arg(root.fmt(modelData.flightTime)).arg(modelData.takeovers).arg(Number(modelData.ownedTime).toFixed(0)).arg(Number(modelData.maxLinkGap).toFixed(1)) }
                        }
                    }

                    Caption { text: qsTr("가드 개입 이력 (눌러서 이동)"); visible: root._loaded && mlAnalysis.interventions.length > 0 }
                    Repeater {
                        model: root._loaded ? mlAnalysis.interventions : []
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28 * u
                            radius: 4 * u
                            color: ivMouse.containsMouse ? MLTheme.panelRaised : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 6 * u; anchors.rightMargin: 6 * u
                                spacing: 8 * u
                                Text { text: root.fmt(modelData.t0); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; Layout.preferredWidth: 36 * u }
                                Text { text: modelData.id; color: MLTheme.vehicleColor(modelData.sysid); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; Layout.preferredWidth: 26 * u }
                                Text { Layout.fillWidth: true; text: Number(modelData.dur).toFixed(1) + " s · " + (modelData.other || "—") + " " + root.m1(modelData.nearest); color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; elide: Text.ElideRight }
                            }
                            MouseArea { id: ivMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.seek(modelData.t0 - 3) }
                        }
                    }

                    Caption { text: qsTr("가드 이벤트") }
                    Repeater {
                        model: root._loaded ? mlAnalysis.events : []
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6 * u
                            Text { text: root.fmt(modelData.t); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; Layout.preferredWidth: 36 * u; Layout.alignment: Qt.AlignTop
                                   MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.seek(modelData.t) } }
                            MLText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.who + " · " + modelData.text; font.pixelSize: MLTheme.fsLabel
                                     color: /※|긴급|두절|실패|lost|fail|danger/i.test(modelData.text) ? MLTheme.caution : MLTheme.label }
                        }
                    }
                }
            }
        }
    }
}
