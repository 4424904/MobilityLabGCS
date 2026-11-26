import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 편대 레인: one row per connected vehicle, above the command bar.
//
//   ▌UAV 01 탠덤 헬기 │ Mission · WP 5/8 ━━━━━━━●──── │ ALT 82 │ GS 14.0 │ BATT ▮▮▮ 72% │ ACACT 감시 · 최근접 18.2 m
//
// The header carries the ACACT Guard link (guard.py on the operator laptop):
// connection, loaded scenario, auto-advance, closest pair, and the commands
// the guard takes from a GCS. 전체 HOLD is one press (it is the safe action);
// 다음 단계 / 재개 / 자동 진행 need two presses.
// Clicking a lane selects that vehicle for the instruments and command bar.
Rectangle {
    id: root

    readonly property real u:       MLTheme.u
    readonly property var  _vehicles: QGroundControl.multiVehicleManager.vehicles
    readonly property var  _active:  QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _g:       typeof mlGuard !== "undefined" && mlGuard.active
    readonly property bool _gSeen:   typeof mlGuard !== "undefined" && mlGuard.seen
    readonly property var  _mc:      globals.planMasterControllerFlyView ? globals.planMasterControllerFlyView.missionController : null
    readonly property real laneH:    44 * u
    readonly property real headerH:  40 * u

    implicitHeight: headerH + Math.max(1, _vehicles.count) * laneH + 1
    radius:         MLTheme.panelRadius
    color:          MLTheme.glass
    border.color:   MLTheme.glassEdge
    clip:           true

    function fv(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }
    // reads mlGuard.drones directly so lanes re-bind on every guard update
    function guardDrone(sysid) {
        if (!_g) return ({})
        var ds = mlGuard.drones
        for (var i = 0; i < ds.length; i++) if (Number(ds[i].sysid) === Number(sysid)) return ds[i]
        return ({})
    }
    function closestFor(id) {
        if (!_g || !id) return null
        var best = null
        var ps = mlGuard.pairs
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i]
            if (p.a !== id && p.b !== id) continue
            var dd = Math.hypot(p.d, p.dz || 0)
            if (!best || dd < best.dist) best = { dist: dd, level: p.level, other: p.a === id ? p.b : p.a }
        }
        return best
    }

    // ---- header --------------------------------------------------------------
    Item {
        id:     header
        width:  parent.width
        height: root.headerH
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }

        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     16 * u
            anchors.verticalCenter: parent.verticalCenter
            spacing:                14 * u

            MLText {
                anchors.verticalCenter: parent.verticalCenter
                text:               qsTr("편대 · %1기").arg(root._vehicles.count)
                font.pixelSize:     MLTheme.fsSmall
                font.weight:        Font.DemiBold
                font.letterSpacing: 1.2 * u
                color:              MLTheme.label
            }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 18 * u; color: MLTheme.line }

            // guard link status
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * u
                Rectangle {
                    id: guardLed
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7 * u; height: width; radius: width / 2
                    color: root._g ? (mlGuard.worstLevel >= 2 ? MLTheme.warning : (mlGuard.worstLevel === 1 || mlGuard.avoiding > 0 ? MLTheme.caution : MLTheme.active)) : (root._gSeen ? MLTheme.warning : MLTheme.faint)
                    SequentialAnimation on opacity {
                        running: root._g && (mlGuard.avoiding > 0 || mlGuard.worstLevel > 0)
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 350 }
                        NumberAnimation { to: 1; duration: 350 }
                        onRunningChanged: if (!running) guardLed.opacity = 1
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ACACT"
                    color: root._g ? MLTheme.text : MLTheme.dim
                    font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 1.2 * u
                }
                MLText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: MLTheme.fsSmall
                    color: root._g ? MLTheme.label : (root._gSeen ? MLTheme.warning : MLTheme.dim)
                    text: {
                        if (!root._g) return qsTr("정지 · [ACACT] 에서 시작")
                        var s = mlGuard.guardEnabled ? qsTr("감시 중") : qsTr("일시정지 (HOLD)")
                        return s + " · " + (mlGuard.autoMode ? qsTr("자동 진행") : qsTr("수동 진행"))
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._g && !isNaN(mlGuard.closest)
                    text: qsTr("최근접 %1 m").arg(Number(mlGuard.closest).toFixed(1))
                    color: mlGuard.worstLevel >= 2 ? MLTheme.warning : (mlGuard.worstLevel === 1 ? MLTheme.caution : MLTheme.text)
                    font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._g && mlGuard.avoiding > 0
                    text: qsTr("회피 중 %1기").arg(mlGuard.avoiding)
                    color: MLTheme.warning
                    font.family: MLTheme.sans; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold
                }
            }
        }

        // guard commands
        Row {
            anchors.right:          parent.right
            anchors.rightMargin:    8 * u
            anchors.verticalCenter: parent.verticalCenter
            spacing:                6 * u

            component GuardButton: MLCommandButton {
                compact:        true
                implicitHeight: 30 * MLTheme.u
                property string guardCmd
                onClicked: {
                    if (mlGuard.sendLine(guardCmd)) MLState.command(qsTr("가드: %1").arg(text))
                    else MLState.log(qsTr("가드 명령 전송 실패: %1").arg(text), 3, 0, "GCS")
                }
            }
            GuardButton { visible: root._g; text: qsTr("다음 단계"); guardCmd: "g"; tone: "go" }
            GuardButton { visible: root._g; text: qsTr("재개"); guardCmd: "r" }
            GuardButton {
                visible:    root._g
                text:       mlGuard.autoMode ? qsTr("자동 진행 끄기") : qsTr("자동 진행 켜기")
                guardCmd:   mlGuard.autoMode ? "auto off" : "auto on"
                selected:   mlGuard.autoMode
                tone:       "active"
            }
            GuardButton { visible: root._g; text: qsTr("전체 HOLD"); guardCmd: "h"; tone: "caution"; twoStep: false }
            MLCommandButton {
                compact:        true
                implicitHeight: 30 * MLTheme.u
                twoStep:        false
                selected:       MLState.guardConsoleOpen
                tone:           "active"
                text:           qsTr("ACACT")
                onClicked:      MLState.guardConsoleOpen = !MLState.guardConsoleOpen
            }
            MLCommandButton {
                compact:        true
                implicitHeight: 30 * MLTheme.u
                twoStep:        false
                selected:       MLState.analysisOpen
                tone:           "active"
                text:           qsTr("분석")
                onClicked:      MLState.analysisOpen = !MLState.analysisOpen
            }
        }
    }

    // ---- lanes ---------------------------------------------------------------
    Column {
        anchors.top:    header.bottom
        width:          parent.width

        MLText {
            visible:        root._vehicles.count === 0
            height:         root.laneH
            leftPadding:    16 * u
            verticalAlignment: Text.AlignVCenter
            text:           qsTr("연결된 기체 없음")
            color:          MLTheme.dim
            font.pixelSize: MLTheme.fsSmall
        }

        Repeater {
            model: root._vehicles

            Item {
                id: lane
                required property var object
                required property int index
                readonly property var  v:        object
                readonly property bool sel:      v === root._active
                readonly property color col:     MLTheme.vehicleColor(v ? v.id : 1)
                readonly property bool lost:     !!v && v.vehicleLinkManager.communicationLost
                readonly property var  gd:       root._g && v ? root.guardDrone(v.id) : ({})
                readonly property bool hasG:     gd && gd.id !== undefined
                readonly property var  near:     hasG ? root.closestFor(gd.id) : null
                readonly property real alt:      v ? root.fv(v.altitudeRelative) : NaN
                readonly property real gs:       v ? root.fv(v.groundSpeed) : NaN
                readonly property var  bat:      v && v.batteries.count > 0 ? v.batteries.get(0) : null
                readonly property real pct:      bat ? root.fv(bat.percentRemaining) : NaN
                // mission progress: QGC's plan for the selected vehicle, otherwise the guard's view
                readonly property int  cur:      sel && root._mc ? root._mc.currentMissionIndex : (hasG ? gd.seq : -1)
                readonly property int  total:    sel && root._mc ? root._mc.visualItems.count - 1 : (hasG ? gd.total : 0)

                width:  root.width
                height: root.laneH

                Rectangle { anchors.fill: parent; color: lane.sel ? Qt.rgba(lane.col.r, lane.col.g, lane.col.b, 0.07) : (laneMouse.containsMouse ? "#0E1317" : "transparent") }
                Rectangle { width: 3 * u; height: parent.height; color: lane.col; opacity: lane.sel ? 1 : 0.45 }
                Rectangle { anchors.bottom: parent.bottom; x: 16 * u; width: parent.width - 32 * u; height: 1; color: MLTheme.hair; visible: lane.index < root._vehicles.count - 1 }

                // identity
                Column {
                    x:      18 * u
                    width:  190 * u
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * u
                    Row {
                        spacing: 8 * u
                        Text { text: "UAV " + ("0" + (lane.v ? lane.v.id : 0)).slice(-2); color: lane.col; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; font.weight: Font.Medium }
                        MLText { text: lane.v ? MLTheme.vehicleTypeName(lane.v) : ""; font.pixelSize: MLTheme.fsSmall; font.weight: lane.sel ? Font.DemiBold : Font.Normal; color: lane.sel ? MLTheme.bright : MLTheme.text }
                        Text { visible: lane.hasG; text: lane.hasG ? lane.gd.id : ""; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MLText {
                        width:  parent.width
                        text:   !lane.v ? "" : (lane.lost ? qsTr("통신 두절") : String(lane.v.flightMode) + (lane.v.armed ? "" : qsTr(" · 시동 꺼짐")))
                        color:  lane.lost ? MLTheme.warning : (lane.v && lane.v.flying ? MLTheme.active : MLTheme.dim)
                        font.pixelSize: MLTheme.fsLabel
                    }
                }

                // progress
                Item {
                    id:     prog
                    x:      218 * u
                    width:  Math.max(80 * u, lane.width - x - 600 * u)
                    height: parent.height
                    readonly property real frac: lane.total > 0 && lane.cur > 0 ? Math.min(1, lane.cur / lane.total) : 0
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2 * u; color: "#1B2026" }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * prog.frac; height: 2 * u; color: lane.col; opacity: 0.9 }
                    Repeater {
                        model: Math.min(lane.total, 40)
                        Rectangle { x: prog.width * (index + 1) / Math.max(1, lane.total) - 1; anchors.verticalCenter: parent.verticalCenter; width: 2 * u; height: 8 * u; color: index + 1 <= lane.cur ? lane.col : "#2A3038"; opacity: 0.8 }
                    }
                    Rectangle {
                        visible: lane.total > 0
                        x: prog.width * prog.frac - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12 * u; height: width; radius: width / 2
                        color: lane.v && lane.v.flying ? lane.col : MLTheme.bg
                        border.color: lane.col; border.width: 2 * u
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.verticalCenter
                        anchors.bottomMargin: 6 * u
                        text: lane.total > 0 ? "WP " + Math.max(0, lane.cur) + "/" + lane.total : qsTr("미션 없음")
                        color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel
                    }
                }

                // numbers
                Row {
                    anchors.right:          parent.right
                    anchors.rightMargin:    16 * u
                    anchors.verticalCenter: parent.verticalCenter
                    spacing:                0

                    component Num: Item {
                        property string label
                        property string value
                        property color  valueColor: MLTheme.text
                        width: 84 * MLTheme.u; height: 44 * MLTheme.u
                        Text { y: 7 * MLTheme.u; text: parent.label; color: MLTheme.faint; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel - 1; font.letterSpacing: 0.8 * MLTheme.u }
                        Text { y: 20 * MLTheme.u; text: parent.value; color: parent.valueColor; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody }
                    }
                    Num { label: "ALT"; value: isNaN(lane.alt) ? "—" : lane.alt.toFixed(1) }
                    Num { label: "GS";  value: isNaN(lane.gs) ? "—" : lane.gs.toFixed(1) }
                    Num {
                        label: "BATT"
                        value: isNaN(lane.pct) ? "—" : lane.pct.toFixed(0) + "%"
                        valueColor: isNaN(lane.pct) ? MLTheme.text : (lane.pct < 20 ? MLTheme.warning : (lane.pct < 35 ? MLTheme.caution : MLTheme.text))
                    }
                    Item {
                        width: 236 * u; height: lane.height
                        Text {
                            y: 7 * u
                            text: "ACACT"
                            color: MLTheme.faint; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel - 1; font.letterSpacing: 0.8 * u
                        }
                        MLText {
                            y: 19 * u
                            width: parent.width
                            font.pixelSize: MLTheme.fsSmall
                            readonly property string gstate: !lane.hasG ? "" : (!lane.gd.fresh ? "lost" : (lane.gd.own ? "own" : (lane.gd.yield ? "yield" : (lane.gd.lock ? "lock" : "watch"))))
                            text: {
                                if (!root._g) return "—"
                                if (!lane.hasG) return qsTr("가드 대상 아님")
                                var t = gstate === "lost" ? qsTr("링크 두절") : gstate === "own" ? qsTr("회피 중") : gstate === "yield" ? qsTr("양보") : gstate === "lock" ? qsTr("조종기 개입") : qsTr("감시")
                                if (lane.near) t += "  " + lane.near.other + " " + lane.near.dist.toFixed(1) + " m"
                                return t
                            }
                            color: gstate === "own" || gstate === "lost" ? MLTheme.warning : (gstate === "lock" || (lane.near && lane.near.level === 1) ? MLTheme.caution : (gstate === "" ? MLTheme.dim : MLTheme.text))
                        }
                    }
                }

                MouseArea {
                    id:             laneMouse
                    anchors.fill:   parent
                    hoverEnabled:   true
                    cursorShape:    Qt.PointingHandCursor
                    onClicked:      if (lane.v) QGroundControl.multiVehicleManager.activeVehicle = lane.v
                }
            }
        }
    }

    MLPanelChrome { radius: root.radius }
}
