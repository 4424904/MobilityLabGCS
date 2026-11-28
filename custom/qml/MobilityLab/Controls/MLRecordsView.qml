import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.FlightMap

// 비행 기록 관리 (v1.2) — every recorded flight (mlRecords).
//   left   list: real/SITL or demo (never mixed), search over name, purpose, site, operator, notes, vehicles
//   right  the selected record: summary (metrics from the record only), replay (2D map + 3D, every
//          vehicle in sync, speed, jump to events, ACACT and link-loss marks on the time bar),
//          charts, events, and the test fields the GCS cannot know (purpose, site, method, notes,
//          the test lead's judgement), PDF / CSV export.
// Replay never talks to a vehicle. While a real vehicle is armed a banner keeps that in view.
Rectangle {
    id: root
    signal closeRequested()
    readonly property real u: MLTheme.u
    readonly property bool _has: typeof mlRecords !== "undefined"
    property string filter: ""            // "" real + SITL · "demo"
    property string tab: "summary"
    property real cursor: 0
    property bool playing: false
    property real speed: 4
    readonly property var replay: _has && mlRecords.loaded ? mlRecords.stateAt(cursor) : []
    readonly property var geo: _has && mlRecords.loaded ? mlRecords.geoTracks() : []
    readonly property bool _realArmed: {
        var vs = QGroundControl.multiVehicleManager.vehicles
        for (var i = 0; i < vs.count; i++) { var v = vs.get(i); if (v.armed && !(typeof mlDemo !== "undefined" && mlDemo.active && mlDemo.isDemoSysid(v.id))) return true }
        return false
    }
    function fmt(v, d, unit) { return (v === undefined || v === null || isNaN(v)) ? qsTr("미기록") : Number(v).toFixed(d) + (unit ? " " + unit : "") }
    function uav(id) { return "UAV " + ("0" + id).slice(-2) }
    function kindName(k) { return k === "demo" ? "DEMO" : (k === "sim" ? "SITL" : qsTr("실비행")) }
    function kindTone(k) { return k === "demo" ? MLTheme.demo : (k === "sim" ? MLTheme.accent : MLTheme.active) }

    color: MLTheme.bg
    Component.onCompleted: if (_has) mlRecords.refresh(filter, "")
    Timer {
        interval: 100; repeat: true; running: root.playing && root.visible
        onTriggered: { root.cursor = Math.min(mlRecords.duration, root.cursor + 0.1 * root.speed); if (root.cursor >= mlRecords.duration) root.playing = false }
    }

    // ---- header ----------------------------------------------------------------------------------
    Rectangle {
        id: head
        width: parent.width; height: 56 * u
        color: MLTheme.panelSolid
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
        Row {
            x: 20 * u; anchors.verticalCenter: parent.verticalCenter; spacing: 14 * u
            MLText { text: qsTr("비행 기록"); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            MLChip { visible: root._has && mlRecords.recording; text: qsTr("● 기록 중 %1").arg(root._has ? mlRecords.current : ""); tone: MLTheme.warning; anchors.verticalCenter: parent.verticalCenter }
            MLText { text: qsTr("저장 위치: %1").arg(root._has ? mlRecords.baseDir : ""); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
            MLIconButton { size: 28 * u; label: qsTr("변경"); enabledState: root._has && !mlRecords.recording; tip: qsTr("기록 저장 위치 바꾸기 (기록 중에는 불가)"); onClicked: folderDlg.open() }
        }
        MLIconButton { anchors.right: parent.right; anchors.rightMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter; glyph: "✕"; label: qsTr("닫기"); onClicked: { root.playing = false; root.closeRequested() } }
    }
    FolderDialog { id: folderDlg; onAccepted: mlRecords.baseDir = selectedFolder }

    // a real aircraft is armed: keep that in view
    Rectangle {
        id: liveBanner
        visible: root._realArmed
        anchors.top: head.bottom; width: parent.width; height: visible ? 36 * u : 0
        color: MLTheme.warningFill
        MLText { anchors.centerIn: parent; text: qsTr("▲ 시동이 걸린 실기체가 있습니다 — 기록 화면은 기체에 아무것도 보내지 않습니다. 관제는 이 창을 닫고 하세요."); color: MLTheme.text; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
    }

    // ---- list --------------------------------------------------------------------------------------
    Rectangle {
        id: list
        anchors.top: liveBanner.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left
        width: 380 * u
        color: MLTheme.panelSolid
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
        Column {
            id: lhead
            x: 14 * u; y: 12 * u; width: parent.width - 28 * u
            spacing: 8 * u
            Row {
                spacing: 4 * u
                MLIconButton { size: 30 * u; label: qsTr("실비행 · SITL"); checked: root.filter === ""; onClicked: { root.filter = ""; mlRecords.refresh("", search.text) } }
                MLIconButton { size: 30 * u; label: qsTr("데모"); checked: root.filter === "demo"; tone: MLTheme.demo; onClicked: { root.filter = "demo"; mlRecords.refresh("demo", search.text) } }
            }
            TextField {
                id: search
                width: parent.width
                placeholderText: qsTr("검색 — 시험명·목적·장소·운용자·메모·기체")
                font.pixelSize: MLTheme.fsSmall
                onTextChanged: mlRecords.refresh(root.filter, text)
            }
        }
        ListView {
            anchors.top: lhead.bottom; anchors.topMargin: 8 * u; anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            model: root._has ? mlRecords.records : []
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                readonly property var r: modelData
                readonly property bool sel: root._has && mlRecords.stamp === r.stamp
                width: ListView.view.width; height: 74 * root.u
                color: sel ? MLTheme.alpha(MLTheme.accent, 0.12) : (rMa.containsMouse ? MLTheme.hover : "transparent")
                Rectangle { visible: parent.sel; width: 3 * root.u; height: parent.height; color: MLTheme.accent }
                Column {
                    x: 16 * root.u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 32 * root.u
                    spacing: 2 * root.u
                    Row {
                        spacing: 8 * root.u
                        Text { text: r.stamp.slice(0, 4) + "-" + r.stamp.slice(4, 6) + "-" + r.stamp.slice(6, 8) + " " + r.stamp.slice(9, 11) + ":" + r.stamp.slice(11, 13); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                        MLChip { text: root.kindName(r.kind); tone: root.kindTone(r.kind) }
                        MLChip { visible: r.recording; text: qsTr("기록 중"); tone: MLTheme.warning }
                    }
                    MLText { text: r.title ? r.title : qsTr("(시험명 없음)"); color: r.title ? MLTheme.bright : MLTheme.dim; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold; width: parent.width; elide: Text.ElideRight }
                    MLText { text: (r.site ? r.site + " · " : "") + r.vehicleText; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; width: parent.width; elide: Text.ElideRight }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
                MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.playing = false; root.cursor = 0; mlRecords.load(r.stamp) } }
            }
            MLText {
                anchors.centerIn: parent
                visible: !root._has || mlRecords.records.length === 0
                width: parent.width - 40 * root.u; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: root.filter === "demo" ? qsTr("데모 기록이 없습니다") : qsTr("비행 기록이 없습니다.\n시동을 걸면 자동으로 기록이 시작됩니다.")
                color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall
            }
        }
    }

    // ---- detail --------------------------------------------------------------------------------------
    Item {
        id: detail
        anchors.top: liveBanner.bottom; anchors.bottom: parent.bottom; anchors.left: list.right; anchors.right: parent.right
        MLText { anchors.centerIn: parent; visible: !root._has || !mlRecords.loaded; text: qsTr("왼쪽에서 기록을 고르세요"); color: MLTheme.dim; font.pixelSize: MLTheme.fsBody }

        Item {
            anchors.fill: parent
            visible: root._has && mlRecords.loaded
            // title row + tabs + export
            Rectangle {
                id: dHead
                width: parent.width; height: 96 * u
                color: MLTheme.panel
                Column {
                    x: 22 * u; y: 12 * u
                    spacing: 6 * u
                    Row {
                        spacing: 10 * u
                        MLText { text: root._has && mlRecords.meta.title ? mlRecords.meta.title : qsTr("비행 기록 %1").arg(root._has ? mlRecords.stamp : ""); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold }
                        MLChip { text: root._has ? root.kindName(mlRecords.meta.kind) : ""; tone: root._has ? root.kindTone(mlRecords.meta.kind) : MLTheme.dim; anchors.verticalCenter: parent.verticalCenter }
                        MLText { text: root._has ? qsTr("GCS %1 · 기록 %2 · %3대").arg(mlRecords.meta.gcsVersion).arg(MLTheme.duration(mlRecords.duration)).arg(mlRecords.vehicles.length) : ""; color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        spacing: 4 * u
                        Repeater {
                            model: [{ k: "summary", t: qsTr("요약") }, { k: "replay", t: qsTr("재생") }, { k: "charts", t: qsTr("그래프") }, { k: "events", t: qsTr("이벤트") }, { k: "fields", t: qsTr("시험 정보 입력") }]
                            MLIconButton { size: 32 * u; label: modelData.t; checked: root.tab === modelData.k; onClicked: root.tab = modelData.k }
                        }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 16 * u; anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * u
                    MLIconButton { size: 34 * u; label: qsTr("PDF 보고서"); onClicked: { var p = mlRecords.exportPdf(""); exportNote.text = p !== "" ? qsTr("저장: %1").arg(p) : qsTr("PDF를 만들지 못했습니다"); if (typeof mlTour !== "undefined" && mlTour) console.log("MLTOUR recpdf " + p) } }
                    MLIconButton { size: 34 * u; label: "CSV"; onClicked: { var p = mlRecords.exportCsv(""); exportNote.text = p !== "" ? qsTr("저장: %1").arg(p) : qsTr("CSV를 만들지 못했습니다") } }
                    MLIconButton { size: 34 * u; label: qsTr("폴더 열기"); onClicked: Qt.openUrlExternally("file:///" + mlRecords.recordDir(mlRecords.stamp)) }
                }
                MLText { id: exportNote; anchors.right: parent.right; anchors.rightMargin: 16 * u; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * u; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
            }

            Item {
                anchors.top: dHead.bottom; anchors.bottom: parent.bottom; width: parent.width

                // ---- summary --------------------------------------------------------------------
                Flickable {
                    anchors.fill: parent
                    visible: root.tab === "summary"
                    contentHeight: sumCol.implicitHeight + 40 * u
                    clip: true
                    ScrollBar.vertical: ScrollBar {}
                    Column {
                        id: sumCol
                        x: 22 * u; y: 18 * u; width: parent.width - 44 * u
                        spacing: 16 * u
                        MLText { width: parent.width; wrapMode: Text.WordWrap; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
                                 text: qsTr("모든 값은 GCS가 받은 텔레메트리 기록(2 Hz)에서 계산했습니다. 받지 못한 값은 '미기록'으로 표시합니다.") }
                        Repeater {
                            model: root._has ? mlRecords.vehicles : []
                            Rectangle {
                                width: sumCol.width; height: vCol.implicitHeight + 28 * u; radius: 10 * u
                                color: MLTheme.tile; border.color: MLTheme.line
                                Rectangle { y: 12 * u; width: 4 * u; height: parent.height - 24 * u; color: MLTheme.vehicleColor(modelData.sysid) }
                                Column {
                                    id: vCol
                                    x: 20 * u; y: 14 * u; width: parent.width - 40 * u
                                    spacing: 10 * u
                                    Row {
                                        spacing: 10 * u
                                        Text { text: root.uav(modelData.sysid); color: MLTheme.vehicleColor(modelData.sysid); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue; font.weight: Font.DemiBold }
                                        MLText { text: modelData.info ? (modelData.info.type + " · " + modelData.info.firmware + " " + modelData.info.fwVersion) : ""; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    Flow {
                                        width: parent.width
                                        spacing: 22 * u
                                        Repeater {
                                            model: [
                                                { l: qsTr("시동 시간"), v: MLTheme.duration(modelData.armedTime) },
                                                { l: qsTr("이동 거리"), v: root.fmt(modelData.distance, 0, "m") },
                                                { l: qsTr("최고 고도"), v: root.fmt(modelData.maxAlt, 1, "m") },
                                                { l: qsTr("평균 / 최고 속도"), v: root.fmt(modelData.meanSpeed, 1, "") + " / " + root.fmt(modelData.maxSpeed, 1, "m/s") },
                                                { l: qsTr("배터리"), v: root.fmt(modelData.battStart, 0, "%") + " → " + root.fmt(modelData.battEnd, 0, "%") },
                                                { l: qsTr("최저 전압"), v: root.fmt(modelData.voltMin, 2, "V") },
                                                { l: qsTr("GNSS 최소 위성 · 최대 HDOP"), v: root.fmt(modelData.minSats, 0, "") + " · " + root.fmt(modelData.maxHdop, 1, "") },
                                                { l: qsTr("통신 두절"), v: qsTr("%1회 · %2").arg(modelData.linkLost).arg(MLTheme.duration(modelData.linkLostTime)) },
                                                { l: qsTr("ACACT 개입"), v: qsTr("%1회 · %2").arg(modelData.acactInterventions).arg(MLTheme.duration(modelData.acactTime)) }
                                            ]
                                            Column {
                                                MLText { text: modelData.l; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                                Text { text: modelData.v; color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue }
                                            }
                                        }
                                    }
                                    MLText {
                                        width: parent.width; wrapMode: Text.WordWrap; color: MLTheme.label; font.pixelSize: MLTheme.fsLabel
                                        text: { var m = modelData.modes, s = []; for (var i = 0; i < m.length && i < 12; i++) s.push(MLTheme.duration(m[i].t) + " " + m[i].mode); return qsTr("비행 모드: ") + s.join(" → ") }
                                    }
                                }
                            }
                        }
                        Repeater {
                            model: root._has ? mlRecords.pairs : []
                            Rectangle {
                                width: sumCol.width; height: 64 * u; radius: 10 * u
                                color: MLTheme.tile; border.color: MLTheme.line
                                Row {
                                    x: 20 * u; anchors.verticalCenter: parent.verticalCenter; spacing: 26 * u
                                    Text { text: root.uav(modelData.a) + " ↔ " + root.uav(modelData.b); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                                    Column { MLText { text: qsTr("최소 수평 이격"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel } Text { text: root.fmt(modelData.minHorizontal, 1, "m"); color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue } }
                                    Column { MLText { text: qsTr("최소 3D 이격"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel } Text { text: root.fmt(modelData.min3d, 1, "m"); color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue } }
                                    Column { MLText { text: qsTr("시각"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel } Text { text: modelData.tMin === null || modelData.tMin === undefined ? "—" : MLTheme.duration(modelData.tMin); color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue } }
                                }
                            }
                        }
                        MLText {
                            visible: root._has && mlRecords.meta.guardLogs !== undefined && mlRecords.meta.guardLogs.length > 0
                            width: parent.width; wrapMode: Text.WordWrap; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
                            text: qsTr("ACACT 가드 기록: %1 — 20 Hz 판단값·개입 사유는 ACACT 분석 화면에서 봅니다.").arg(root._has && mlRecords.meta.guardLogs ? mlRecords.meta.guardLogs.join(", ") : "")
                        }
                    }
                }

                // ---- replay: 2D map + 3D, one time bar -------------------------------------------------------
                Item {
                    anchors.fill: parent
                    visible: root.tab === "replay"
                    FlightMap {
                        id: rmap
                        mapName: "mlRecordsMap"
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: bar.top
                        width: parent.width * 0.55
                        allowGCSLocationCenter: false
                        allowVehicleLocationCenter: false
                        function fitRecord() {
                            if (!root._has || !mlRecords.loaded) return
                            var e = mlRecords.extent
                            if (e.latMax < e.latMin) return
                            visibleRegion = QtPositioning.rectangle(QtPositioning.coordinate(e.latMax + 0.0004, e.lonMin - 0.0006), QtPositioning.coordinate(e.latMin - 0.0004, e.lonMax + 0.0006))
                        }
                        Connections { target: root._has ? mlRecords : null; function onLoadedChanged() { rmap.fitRecord() } }
                        Component.onCompleted: fitRecord()
                        onVisibleChanged: if (visible) fitRecord()
                        MapItemView {
                            model: root.geo
                            delegate: MapPolyline {
                                line.width: 3
                                line.color: MLTheme.vehicleColor(modelData.sysid)
                                path: modelData.path
                            }
                        }
                        MapItemView {
                            model: root.replay
                            delegate: MapQuickItem {
                                coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                                anchorPoint.x: mk.width / 2; anchorPoint.y: mk.height / 2
                                sourceItem: Item {
                                    id: mk
                                    width: 34 * root.u; height: 34 * root.u
                                    Rectangle { anchors.fill: parent; radius: width / 2; color: modelData.own ? MLTheme.warning : MLTheme.vehicleColor(modelData.sysid); border.color: "white"; border.width: 2; opacity: modelData.lost ? 0.45 : 1 }
                                    Text { anchors.centerIn: parent; text: "▲"; rotation: isNaN(modelData.hdg) ? 0 : modelData.hdg; color: "white"; font.pixelSize: 14 * root.u }
                                    Rectangle {
                                        x: parent.width + 4 * root.u; y: -4 * root.u
                                        width: lt.implicitWidth + 10 * root.u; height: lt.implicitHeight + 4 * root.u; radius: 3 * root.u
                                        color: MLTheme.glass
                                        Text { id: lt; anchors.centerIn: parent; text: root.uav(modelData.sysid) + "  " + Number(modelData.alt).toFixed(1) + " m" + (modelData.lost ? qsTr("  두절") : ""); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                                    }
                                }
                            }
                        }
                    }
                    Loader {
                        anchors.left: rmap.right; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: bar.top
                        active: root.tab === "replay" && root.visible
                        sourceComponent: Component {
                            MLAcact3D {
                                replay: true; replayGeo: true
                                detachable: false; closable: false
                                replayDrones: root.replay
                                replayTracks: root.geo
                                replayCursor: root.cursor
                            }
                        }
                    }
                    // time bar: play, speed, scrub, event / ACACT / link marks, jump to next event
                    Rectangle {
                        id: bar
                        anchors.bottom: parent.bottom; width: parent.width; height: 86 * u
                        color: MLTheme.panelSolid
                        Rectangle { width: parent.width; height: 1; color: MLTheme.line }
                        Row {
                            x: 16 * u; y: 10 * u; spacing: 8 * u
                            MLIconButton { size: 34 * u; glyph: root.playing ? "" : "▶"; label: root.playing ? qsTr("일시정지") : qsTr("재생"); onClicked: { if (root.cursor >= mlRecords.duration) root.cursor = 0; root.playing = !root.playing } }
                            Repeater { model: [1, 2, 4, 8, 16]; MLIconButton { size: 34 * u; label: modelData + "×"; checked: root.speed === modelData; onClicked: root.speed = modelData } }
                            MLIconButton {
                                size: 34 * u; label: qsTr("다음 이벤트 ›")
                                onClicked: { var ev = mlRecords.events; for (var i = 0; i < ev.length; i++) if (ev[i].t > root.cursor + 0.5) { root.cursor = ev[i].t; return } }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: MLTheme.duration(root.cursor) + " / " + MLTheme.duration(root._has ? mlRecords.duration : 0); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody }
                        }
                        Item {
                            id: track
                            x: 16 * u; y: 54 * u; width: parent.width - 32 * u; height: 22 * u
                            readonly property real dur: Math.max(1, root._has ? mlRecords.duration : 1)
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4 * u; radius: 2 * u; color: MLTheme.line }
                            // ACACT and link-loss stretches of every vehicle
                            Repeater {
                                model: root._has ? mlRecords.vehicles : []
                                Repeater {
                                    model: modelData.series
                                    Rectangle {
                                        visible: modelData[5] === 1 || modelData[6] === 1
                                        x: track.width * modelData[0] / track.dur; y: modelData[6] === 1 ? 2 * u : 14 * u
                                        width: Math.max(2, track.width / track.dur); height: 6 * u
                                        color: modelData[6] === 1 ? MLTheme.warning : MLTheme.caution
                                    }
                                }
                            }
                            Repeater {
                                model: root._has ? mlRecords.events : []
                                Rectangle {
                                    visible: modelData.level >= 2
                                    x: track.width * modelData.t / track.dur - 1; y: 0; width: 2; height: track.height
                                    color: modelData.level >= 3 ? MLTheme.warning : MLTheme.caution; opacity: 0.8
                                }
                            }
                            Rectangle { x: track.width * root.cursor / track.dur - 6 * u; anchors.verticalCenter: parent.verticalCenter; width: 12 * u; height: 12 * u; radius: 6 * u; color: MLTheme.accent }
                            MouseArea { anchors.fill: parent; onPressed: (m) => root.cursor = Math.max(0, Math.min(track.dur, m.x / track.width * track.dur)); onPositionChanged: (m) => { if (pressed) root.cursor = Math.max(0, Math.min(track.dur, m.x / track.width * track.dur)) } }
                        }
                        MLText { anchors.right: parent.right; anchors.rightMargin: 16 * u; y: 14 * u; text: qsTr("빨강 = ACACT 제어 · 노랑 = 통신 두절 · 세로선 = 경고"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                    }
                }

                // ---- charts, linked to the replay time --------------------------------------------------
                Flickable {
                    anchors.fill: parent
                    visible: root.tab === "charts"
                    contentHeight: chCol.implicitHeight + 30 * u
                    clip: true
                    Column {
                        id: chCol
                        x: 22 * u; y: 16 * u; width: parent.width - 44 * u
                        spacing: 14 * u
                        Repeater {
                            model: [{ t: qsTr("상대 고도 (m)"), i: 1 }, { t: qsTr("지면 속도 (m/s)"), i: 2 }, { t: qsTr("배터리 (%)"), i: 3 }, { t: qsTr("배터리 전압 (V)"), i: 4 }, { t: qsTr("기체 쌍 수평 이격 (m)"), i: -1 }]
                            Column {
                                width: chCol.width
                                spacing: 4 * u
                                visible: modelData.i >= 0 || (root._has && mlRecords.pairs.length > 0)
                                MLText { text: modelData.t; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
                                Canvas {
                                    id: cv
                                    width: parent.width; height: 150 * u
                                    readonly property int idx: modelData.i
                                    property real cur: root.cursor
                                    onCurChanged: requestPaint()
                                    Connections { target: root._has ? mlRecords : null; function onLoadedChanged() { cv.requestPaint() } }
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        var c = getContext("2d"); c.reset()
                                        if (!root._has || !mlRecords.loaded) return
                                        var dur = Math.max(1, mlRecords.duration), lines = [], mx = 1
                                        if (idx >= 0) {
                                            var vs = mlRecords.vehicles
                                            for (var i = 0; i < vs.length; i++) {
                                                var s = vs[i].series, l = []
                                                for (var k = 0; k < s.length; k++) if (s[k][idx] !== null && s[k][idx] !== undefined) { l.push([s[k][0], s[k][idx]]); mx = Math.max(mx, s[k][idx]) }
                                                lines.push({ c: MLTheme.vehicleColor(vs[i].sysid), p: l })
                                            }
                                        } else {
                                            var ps = mlRecords.pairs
                                            for (var j = 0; j < ps.length; j++) {
                                                var l2 = []
                                                for (var q = 0; q < ps[j].series.length; q++) { l2.push([ps[j].series[q][0], ps[j].series[q][1]]); mx = Math.max(mx, ps[j].series[q][1]) }
                                                lines.push({ c: MLTheme.vehicleColor(ps[j].b), p: l2 })
                                            }
                                        }
                                        mx = idx === 3 ? 100 : mx * 1.15
                                        var L = 40, W = width - L - 8, H = height - 18
                                        c.strokeStyle = MLTheme.line; c.lineWidth = 1; c.fillStyle = MLTheme.dim; c.font = Math.round(11 * root.u) + "px sans-serif"
                                        for (var g = 0; g <= 4; g++) { var y = H - H * g / 4 + 4; c.beginPath(); c.moveTo(L, y); c.lineTo(L + W, y); c.stroke(); c.fillText((mx * g / 4).toFixed(mx < 20 ? 1 : 0), 2, y + 4) }
                                        for (var a = 0; a < lines.length; a++) {
                                            c.strokeStyle = lines[a].c; c.lineWidth = 1.6; c.beginPath()
                                            for (var b = 0; b < lines[a].p.length; b++) { var px = L + W * lines[a].p[b][0] / dur, py = H - H * Math.min(1, lines[a].p[b][1] / mx) + 4; if (b === 0) c.moveTo(px, py); else c.lineTo(px, py) }
                                            c.stroke()
                                        }
                                        c.strokeStyle = MLTheme.accent; c.lineWidth = 1.5; c.beginPath(); var cx = L + W * root.cursor / dur; c.moveTo(cx, 0); c.lineTo(cx, H + 6); c.stroke()
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: (m) => { root.cursor = Math.max(0, (m.x - 40) / (cv.width - 48) * mlRecords.duration) } }
                                }
                            }
                        }
                    }
                }

                // ---- events -----------------------------------------------------------------------------
                ListView {
                    anchors.fill: parent; anchors.margins: 16 * u
                    visible: root.tab === "events"
                    clip: true
                    model: root._has ? mlRecords.events : []
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        width: ListView.view.width; height: 34 * root.u
                        color: evMa.containsMouse ? MLTheme.hover : (index % 2 ? "transparent" : MLTheme.tile)
                        Row {
                            x: 10 * root.u; anchors.verticalCenter: parent.verticalCenter; spacing: 12 * root.u
                            Text { text: modelData.time; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; width: 70 * root.u }
                            Text { text: MLTheme.duration(modelData.t); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; width: 60 * root.u }
                            MLText { text: ["", qsTr("정보"), qsTr("주의"), qsTr("위험"), qsTr("긴급")][Math.max(0, Math.min(4, modelData.level))] || qsTr("정보"); color: modelData.level >= 3 ? MLTheme.warning : (modelData.level === 2 ? MLTheme.caution : MLTheme.dim); font.pixelSize: MLTheme.fsSmall; width: 44 * root.u }
                            MLText { text: modelData.sysid > 0 ? root.uav(modelData.sysid) : "—"; color: modelData.sysid > 0 ? MLTheme.vehicleColor(modelData.sysid) : MLTheme.dim; font.pixelSize: MLTheme.fsSmall; width: 60 * root.u }
                            MLText { text: modelData.text; color: MLTheme.text; font.pixelSize: MLTheme.fsSmall }
                        }
                        MouseArea { id: evMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.cursor = modelData.t; root.tab = "replay" } }
                    }
                    MLText { anchors.centerIn: parent; visible: !root._has || mlRecords.events.length === 0; text: qsTr("기록된 이벤트가 없습니다"); color: MLTheme.dim }
                }

                // ---- test fields --------------------------------------------------------------------------
                Flickable {
                    anchors.fill: parent
                    visible: root.tab === "fields"
                    contentHeight: fCol.implicitHeight + 40 * u
                    clip: true
                    Column {
                        id: fCol
                        x: 22 * u; y: 18 * u; width: Math.min(900 * u, parent.width - 44 * u)
                        spacing: 10 * u
                        MLText { width: parent.width; wrapMode: Text.WordWrap; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
                                 text: qsTr("GCS가 알 수 없는 항목입니다. 입력한 내용은 기록 폴더의 meta.json에 저장되고 보고서에 들어갑니다. 비워 두면 보고서에 '미입력'으로 나옵니다.") }
                        Repeater {
                            id: fields
                            model: [{ k: "title", t: qsTr("시험명") }, { k: "purpose", t: qsTr("시험 목적") }, { k: "site", t: qsTr("시험 장소") }, { k: "operator", t: qsTr("운용자") },
                                    { k: "method", t: qsTr("시험 방법") }, { k: "conditions", t: qsTr("시험 환경 · 조건 (기상 등)") }, { k: "notes", t: qsTr("특이사항 · 메모") }]
                            Column {
                                width: fCol.width
                                property alias value: tf.text
                                MLText { text: modelData.t; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                                TextField { id: tf; width: parent.width; font.pixelSize: MLTheme.fsBody; text: root._has && mlRecords.meta[modelData.k] ? mlRecords.meta[modelData.k] : "" }
                            }
                        }
                        MLSectionTitle { text: qsTr("시험 책임자 판단 (자동 집계와 별개)"); width: parent.width }
                        Row {
                            spacing: 6 * u
                            property string pick: root._has && mlRecords.meta.judgement ? mlRecords.meta.judgement : ""
                            id: judge
                            Repeater {
                                model: [{ k: "pass", t: qsTr("적합") }, { k: "fail", t: qsTr("부적합") }, { k: "hold", t: qsTr("보류") }, { k: "", t: qsTr("미판정") }]
                                MLIconButton { size: 34 * u; label: modelData.t; checked: judge.pick === modelData.k; onClicked: judge.pick = modelData.k }
                            }
                        }
                        TextField { id: jnote; width: parent.width; placeholderText: qsTr("판단 근거"); font.pixelSize: MLTheme.fsBody; text: root._has && mlRecords.meta.judgementNote ? mlRecords.meta.judgementNote : "" }
                        Row {
                            spacing: 10 * u
                            MLCommandButton {
                                text: qsTr("저장"); twoStep: false; tone: "go"
                                onClicked: {
                                    var f = { judgement: judge.pick, judgementNote: jnote.text }
                                    for (var i = 0; i < fields.count; i++) f[fields.model[i].k] = fields.itemAt(i).value
                                    saved.text = mlRecords.setUserFields(mlRecords.stamp, f) ? qsTr("저장했습니다") : qsTr("저장하지 못했습니다")
                                }
                            }
                            MLText { id: saved; anchors.verticalCenter: parent.verticalCenter; color: MLTheme.active; font.pixelSize: MLTheme.fsSmall }
                        }
                    }
                }
            }
        }
    }
}
