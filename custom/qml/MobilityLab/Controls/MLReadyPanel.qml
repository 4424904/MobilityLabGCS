import QtQuick
import QtQuick.Controls

import QGroundControl

// STANDARD mode, left panel "비행 준비": everything a first-time operator needs, in order.
//   1. connection   — what the GCS is listening on, every vehicle it found and its link state
//   2. readiness    — per vehicle GO / 확인 필요 / 비행 불가 with the reasons in plain words
//   3. key numbers  — of the selected (command target) vehicle: altitude, speed, battery, home
//   4. next steps   — pre-flight check, mission planning, practice in the demo
// The readiness values are the integrated pre-flight check (MLReadiness), nothing new is computed.
Item {
    id: root
    readonly property real u:       MLTheme.u
    readonly property var  _vs:     QGroundControl.multiVehicleManager.vehicles
    readonly property var  _active: QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _g:      typeof mlGuard !== "undefined"
    readonly property bool _demo:   typeof mlDemo !== "undefined" && mlDemo.active
    property int _tick: 0
    Timer { interval: 1000; running: root.visible; repeat: true; onTriggered: root._tick++ }

    function fv(f) { return MLReadiness.fv(f) }
    function sum(v) { _tick; return MLReadiness.summary(v, _g ? mlGuard.preflight : [], _g ? mlGuard.missionCheck : ({}), _g) }

    Flickable {
        anchors.fill:   parent
        contentHeight:  col.implicitHeight + 24 * u
        clip:           true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id:      col
            x:       14 * u
            y:       12 * u
            width:   root.width - 28 * u
            spacing: 14 * u

            // ---- 1. connection ------------------------------------------------------------
            MLSectionTitle { text: qsTr("1  기체 연결"); width: parent.width }
            Rectangle {
                visible: root._vs.count === 0
                width: parent.width
                height: emptyCol.implicitHeight + 32 * u
                radius: 10 * u
                color: MLTheme.tile
                border.color: MLTheme.line
                Column {
                    id: emptyCol
                    x: 16 * u; y: 16 * u; width: parent.width - 32 * u
                    spacing: 10 * u
                    Row {
                        spacing: 10 * u
                        MLWaitIndicator { anchors.verticalCenter: parent.verticalCenter }
                        MLText { anchors.verticalCenter: parent.verticalCenter; text: qsTr("기체를 찾는 중"); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold }
                    }
                    MLText {
                        width: parent.width; wrapMode: Text.WordWrap; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall
                        text: qsTr("UDP 14550(텔레메트리 모뎀·SITL)과 USB·시리얼 포트를 자동으로 살피고 있습니다. 기체 전원을 켜고 모뎀을 연결하면 여기에 나타납니다.")
                    }
                    Row {
                        spacing: 8 * u
                        MLCommandButton { compact: true; twoStep: false; text: qsTr("시작 안내"); onClicked: MLState.onboardingOpen = true }
                        MLCommandButton { compact: true; twoStep: false; text: qsTr("데모로 연습"); tone: "active"; onClicked: MLState.demoOpen = true }
                    }
                }
            }

            // ---- 2. readiness per vehicle -----------------------------------------------------
            Repeater {
                model: root._vs
                Rectangle {
                    id: card
                    required property var object
                    readonly property var  v:       object
                    readonly property bool sel:     v === root._active
                    readonly property bool lost:    v.vehicleLinkManager.communicationLost
                    readonly property var  s:       root.sum(v)
                    readonly property color stTone: lost ? MLTheme.warning : (v.armed ? MLTheme.caution : (s.level === 2 ? MLTheme.active : (s.level === 1 ? MLTheme.caution : MLTheme.warning)))
                    readonly property string stText: lost ? qsTr("통신 두절") : (v.flying ? qsTr("비행 중") : (v.armed ? qsTr("시동 걸림") : (s.level === 2 ? qsTr("비행 가능") : (s.level === 1 ? qsTr("확인 필요") : qsTr("비행 불가")))))
                    readonly property real pct: v.batteries.count > 0 ? root.fv(v.batteries.get(0).percentRemaining) : NaN
                    width: col.width
                    height: cardCol.implicitHeight + 24 * u
                    radius: 10 * u
                    color: sel ? MLTheme.panelRaised : MLTheme.tile
                    border.color: sel ? MLTheme.alpha(MLTheme.vehicleColor(v.id), 0.9) : MLTheme.line
                    border.width: sel ? 2 : 1
                    Rectangle { x: 0; y: 10 * u; width: 4 * u; height: parent.height - 20 * u; radius: 2 * u; color: MLTheme.vehicleColor(card.v.id) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: QGroundControl.multiVehicleManager.activeVehicle = card.v }

                    Column {
                        id: cardCol
                        x: 16 * u; y: 12 * u; width: parent.width - 30 * u
                        spacing: 8 * u
                        Item {
                            width: parent.width; height: 30 * u
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8 * u
                                Text { anchors.verticalCenter: parent.verticalCenter; text: MLTheme.uavName(card.v.id); color: MLTheme.vehicleColor(card.v.id); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                                MLText { anchors.verticalCenter: parent.verticalCenter; text: MLTheme.vehicleTypeName(card.v); color: MLTheme.text; font.pixelSize: MLTheme.fsBody }
                                MLChip { anchors.verticalCenter: parent.verticalCenter; visible: root._demo && mlDemo.isDemoSysid(card.v.id); text: "DEMO"; tone: MLTheme.demo }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                width: stLab.implicitWidth + 20 * u; height: 28 * u; radius: 14 * u
                                color: MLTheme.alpha(card.stTone, 0.16); border.color: card.stTone
                                MLText { id: stLab; anchors.centerIn: parent; text: card.stText; color: card.stTone; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
                            }
                        }
                        // compact status line: link · mode · battery · GNSS
                        Row {
                            spacing: 14 * u
                            Repeater {
                                model: card.s.checks.slice(0, 3)
                                Row {
                                    spacing: 5 * u
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7 * u; height: width; radius: width / 2; color: modelData.s === 2 ? MLTheme.active : (modelData.s === 0 ? MLTheme.warning : (modelData.s === 1 ? MLTheme.caution : MLTheme.faint)) }
                                    MLText { text: modelData.k; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                }
                            }
                            MLText { text: card.v.flightMode; color: MLTheme.label; font.pixelSize: MLTheme.fsLabel }
                        }
                        // plain-language reasons (fails first), only for the selected vehicle or a no-go one
                        Column {
                            width: parent.width
                            spacing: 4 * u
                            visible: !card.v.armed && (card.sel || card.s.level === 0) && (card.s.reasons.length + card.s.notes.length) > 0
                            Repeater {
                                model: card.s.reasons.concat(card.sel ? card.s.notes : []).slice(0, card.sel ? 5 : 2)
                                Row {
                                    width: parent.width
                                    spacing: 8 * u
                                    readonly property bool fail: index < card.s.reasons.length
                                    Text { text: parent.fail ? "✕" : "!"; color: parent.fail ? MLTheme.warning : MLTheme.caution; font.pixelSize: MLTheme.fsSmall; font.weight: Font.Bold; width: 12 * u }
                                    MLText { width: parent.width - 20 * u; text: modelData; wrapMode: Text.WordWrap; color: parent.fail ? MLTheme.text : MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                                }
                            }
                        }
                        // key numbers of the command target
                        Row {
                            visible: card.sel
                            spacing: 18 * u
                            Repeater {
                                model: [
                                    { l: qsTr("고도"), v: root.fv(card.v.altitudeRelative), d: 1, u: "m" },
                                    { l: qsTr("속도"), v: root.fv(card.v.groundSpeed), d: 1, u: "m/s" },
                                    { l: qsTr("배터리"), v: card.pct, d: 0, u: "%" },
                                    { l: qsTr("홈 거리"), v: root.fv(card.v.distanceToHome), d: 0, u: "m" }
                                ]
                                Column {
                                    spacing: 0
                                    MLText { text: modelData.l; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                    Row {
                                        spacing: 3 * u
                                        Text { id: num; text: MLTheme.formatValue(modelData.v, modelData.d); color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBig; font.weight: Font.Medium }
                                        MLText { anchors.baseline: num.baseline; text: modelData.u; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- 3. next steps -------------------------------------------------------------------
            MLSectionTitle { text: qsTr("2  비행 준비"); width: parent.width; visible: root._vs.count > 0 }
            Column {
                visible: root._vs.count > 0
                width: parent.width
                spacing: 8 * u
                Repeater {
                    model: [
                        { t: qsTr("비행 전 통합 점검"), d: qsTr("통신·GNSS·배터리·기체 상태·펌웨어·미션·ACACT"), a: "preflight" },
                        { t: qsTr("미션 계획"), d: qsTr("경로를 만들고 업로드 · 오류는 자동 검사"), a: "plan" },
                        { t: qsTr("ACACT 다기체 운용"), d: qsTr("2기 이상 · 가드 시작과 일괄 시작은 ACACT 콘솔에서"), a: "acact" }
                    ]
                    Rectangle {
                        width: parent.width; height: 56 * u; radius: 8 * u
                        visible: modelData.a !== "acact" || root._vs.count > 1
                        color: stepMa.containsMouse ? MLTheme.hover : MLTheme.tile
                        border.color: MLTheme.line
                        Column {
                            x: 14 * u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 50 * u
                            MLText { text: modelData.t; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                            MLText { text: modelData.d; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; width: parent.width; elide: Text.ElideRight }
                        }
                        Text { anchors.right: parent.right; anchors.rightMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter; text: "›"; color: MLTheme.accent; font.pixelSize: 22 * u }
                        MouseArea {
                            id: stepMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.a === "preflight") MLState.preflightOpen = true
                                else if (modelData.a === "plan") mainWindow.showPlanView()
                                else MLState.guardConsoleOpen = true
                            }
                        }
                    }
                }
            }
        }
    }
}
