import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// ACACT 운용 패널 — the built-in guard (MLAcactRuntime), no terminal, no external program.
//
//   운용     [가드 시작/종료] · [일괄 시작] · [다음 단계] [대기 기체만] · [자동 진행] · [전체 HOLD] [재개]
//            기체별 상태(감시/회피/양보/조종기·운용자 우선/두절) · 기체 간 거리 · 최소 이격 기록
//   사전점검  기체별 점검 결과
//   설정     시연 구역(원점·방위) · 판단/해제/회피/ACACT/통신 파라미터 (기본값 표시, 복원)
//   지원범위  ACACT 지원 범위와 안전 동작
//
// Commands that move vehicles take two presses; 전체 HOLD takes one.
Rectangle {
    id: root

    signal closeRequested()

    readonly property real u:       MLTheme.u
    readonly property bool _run:    typeof mlGuard !== "undefined" && mlGuard.running
    property int  tab:              0

    implicitWidth:  560 * u
    color:          MLTheme.glassStrong
    radius:         MLTheme.panelRadius
    border.color:   MLTheme.glassEdgeHi

    function stateText(d) {
        if (!d.connected) return qsTr("연결 끊김")
        if (!d.fresh) return qsTr("텔레메트리 두절")
        if (d.own) return qsTr("회피 중")
        if (d.yield) return qsTr("양보")
        if (d.lock) return qsTr("조종기/운용자 우선")
        if (!d.supported) return qsTr("장애물로 고려")
        return qsTr("감시")
    }
    function stateColor(d) {
        if (!d.connected || !d.fresh || d.own) return MLTheme.warning
        if (d.lock || d.yield) return MLTheme.caution
        if (!d.supported) return MLTheme.dim
        return MLTheme.active
    }

    component Btn: MLCommandButton { compact: true; implicitHeight: 34 * MLTheme.u }
    component Caption: MLText { color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.8 * MLTheme.u }

    ColumnLayout {
        anchors.fill:       parent
        anchors.margins:    16 * u
        spacing:            10 * u

        // ---- header ---------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * u
            Rectangle {
                width: 8 * u; height: width; radius: width / 2
                color: !root._run ? MLTheme.faint : (mlGuard.worstLevel >= 2 ? MLTheme.warning : (mlGuard.avoiding > 0 || mlGuard.worstLevel === 1 ? MLTheme.caution : MLTheme.active))
            }
            MLText { text: qsTr("ACACT 충돌 회피"); font.pixelSize: MLTheme.fsValue; font.weight: Font.DemiBold; color: MLTheme.bright }
            MLText {
                Layout.fillWidth: true
                font.pixelSize: MLTheme.fsSmall
                color: MLTheme.dim
                elide: Text.ElideRight
                text: !root._run ? qsTr("정지") : (mlGuard.guardEnabled ? qsTr("감시 중 · %1").arg(MLTheme.duration(mlGuard.guardTime)) : qsTr("일시정지 (전체 HOLD)"))
            }
            Rectangle {
                Layout.preferredWidth: 30 * u; Layout.preferredHeight: 30 * u
                radius: 4 * u
                color: closeMouse.containsMouse ? MLTheme.panelRaised : "transparent"
                border.color: MLTheme.line
                Text { anchors.centerIn: parent; text: "✕"; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
            }
        }

        // ---- tabs -----------------------------------------------------------
        Row {
            Layout.fillWidth: true
            spacing: 2 * u
            Repeater {
                model: [qsTr("운용"), qsTr("사전 점검"), qsTr("설정"), qsTr("지원 범위")]
                Rectangle {
                    required property int index
                    required property string modelData
                    width: tabText.implicitWidth + 24 * u; height: 30 * u; radius: 4 * u
                    color: root.tab === index ? MLTheme.panelRaised : "transparent"
                    border.color: root.tab === index ? MLTheme.lineStrong : "transparent"
                    MLText { id: tabText; anchors.centerIn: parent; text: parent.modelData; font.pixelSize: MLTheme.fsSmall; color: root.tab === parent.index ? MLTheme.text : MLTheme.dim }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = parent.index }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: MLTheme.line }

        // ================= 운용 =================
        ColumnLayout {
            visible: root.tab === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10 * u

            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * u
                Btn {
                    visible: !root._run
                    text: qsTr("가드 시작"); tone: "go"; twoStep: false
                    available: QGroundControl.multiVehicleManager.vehicles.count > 0
                    disabledReason: qsTr("연결된 기체가 없습니다")
                    onClicked: { if (mlGuard.start()) MLState.command(qsTr("ACACT 가드 시작")) }
                }
                Btn {
                    visible: root._run
                    text: qsTr("가드 종료"); tone: "caution"
                    onClicked: { mlGuard.stop(); MLState.command(qsTr("ACACT 가드 종료")) }
                }
                Btn {
                    text: mlGuard.startInProgress ? qsTr("일괄 시작 중단") : qsTr("일괄 시작 (시동·이륙)")
                    tone: mlGuard.startInProgress ? "caution" : "go"
                    available: root._run && mlGuard.guardEnabled
                    disabledReason: qsTr("가드를 먼저 시작하세요")
                    onClicked: { if (mlGuard.startInProgress) mlGuard.abortStart(); else mlGuard.startFlight() }
                }
                Item { Layout.fillWidth: true }
                Btn { text: qsTr("전체 HOLD"); tone: "caution"; twoStep: false; onClicked: { mlGuard.holdAll(); MLState.command(qsTr("전체 HOLD")) } }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6 * u
                Btn { text: qsTr("다음 단계"); tone: "go"; available: root._run; onClicked: mlGuard.sync(false) }
                Btn { text: qsTr("대기 기체만 출발"); available: root._run; onClicked: mlGuard.sync(true) }
                Btn { text: qsTr("재개"); available: root._run && !mlGuard.guardEnabled; onClicked: mlGuard.resume() }
                Btn {
                    text: mlGuard.autoMode ? qsTr("자동 진행 켜짐") : qsTr("자동 진행 꺼짐")
                    tone: "active"; selected: mlGuard.autoMode; twoStep: false
                    onClicked: mlGuard.autoMode = !mlGuard.autoMode
                }
            }

            // ---- scenario (scenarios.py → build, upload, verify; guard.py `load`) ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: scCol.implicitHeight + 20 * u
                radius: 6 * u
                color: "#0D1115"
                border.color: mlGuard.scenario !== "" ? "#244A3A" : MLTheme.line
                ColumnLayout {
                    id: scCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 10 * u
                    spacing: 8 * u
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8 * u
                        Caption { text: qsTr("시나리오") }
                        MLText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: MLTheme.fsSmall
                            color: mlGuard.busyText !== "" ? MLTheme.caution : (mlGuard.scenario !== "" ? MLTheme.active : MLTheme.dim)
                            text: mlGuard.busyText !== "" ? mlGuard.busyText
                                  : mlGuard.scenario !== "" ? qsTr("준비됨 · %1 / %2").arg(mlGuard.scenario).arg(mlGuard.scenarioMode === "demo" ? qsTr("본 시연") : qsTr("리허설"))
                                  : mlGuard.activeIds === "" ? qsTr("제어 가능한 PX4 기체 없음") : qsTr("미업로드 · 대상 %1").arg(mlGuard.activeIds)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8 * u
                        QGCComboBox {
                            id: scCombo
                            Layout.fillWidth: true
                            model: mlGuard.scenarios
                            textRole: "title"
                            enabled: mlGuard.scenarios.length > 0
                        }
                        Btn { text: qsTr("본 시연"); tone: "active"; twoStep: false; selected: scMode.demo; onClicked: scMode.demo = true }
                        Btn { text: qsTr("리허설"); tone: "active"; twoStep: false; selected: !scMode.demo; onClicked: scMode.demo = false }
                        QtObject { id: scMode; property bool demo: false }
                        Btn {
                            text: qsTr("업로드")
                            tone: "go"
                            readonly property var _sel: scCombo.currentIndex >= 0 && scCombo.currentIndex < mlGuard.scenarios.length ? mlGuard.scenarios[scCombo.currentIndex] : null
                            available: _sel !== null && _sel.available && mlGuard.site.lat !== undefined && mlGuard.busyText === ""
                            disabledReason: mlGuard.site.lat === undefined ? qsTr("설정 탭에서 시연 구역을 먼저 정하세요")
                                           : (_sel !== null && !_sel.available) ? qsTr("이 기체 수에서는 쓸 수 없는 시나리오")
                                           : qsTr("업로드 진행 중")
                            onClicked: mlGuard.loadScenario(_sel.name, scMode.demo ? "demo" : "rehearsal")
                        }
                    }
                    MLText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: MLTheme.fsLabel
                        color: MLTheme.faint
                        text: qsTr("리허설 = 기체별 층 고도로 수직 분리 · 본 시연 = 시나리오 공통 고도. 지상·시동 꺼짐 상태에서만 업로드됩니다.")
                    }
                }
            }

            Caption { text: qsTr("기체"); Layout.topMargin: 4 * u }
            Repeater {
                model: root._run ? mlGuard.drones : []
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44 * u
                    radius: 6 * u
                    color: modelData.own ? "#24120C0D" : "#0D1115"
                    border.color: modelData.own ? "#6B3430" : MLTheme.line
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12 * u
                        anchors.rightMargin: 12 * u
                        spacing: 12 * u
                        Rectangle { Layout.preferredWidth: 3 * u; Layout.preferredHeight: 24 * u; color: MLTheme.vehicleColor(modelData.sysid) }
                        Text { text: modelData.id; color: MLTheme.vehicleColor(modelData.sysid); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; Layout.preferredWidth: 32 * u }
                        MLText { text: root.stateText(modelData); color: root.stateColor(modelData); font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; Layout.preferredWidth: 120 * u }
                        Text { text: modelData.mode; color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; Layout.preferredWidth: 80 * u }
                        Text { text: Number(modelData.alt).toFixed(1) + " m"; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; Layout.preferredWidth: 64 * u }
                        Item { Layout.fillWidth: true }
                        Text { text: qsTr("개입 %1").arg(modelData.takeovers); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                    }
                }
            }
            MLText {
                visible: !root._run
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: MLTheme.dim
                font.pixelSize: MLTheme.fsSmall
                text: qsTr("가드를 시작하면 연결된 모든 기체를 감시합니다. 충돌이 예측되면 PX4 멀티콥터를 Offboard 로 잠시 넘겨받아 피하고, 위험이 사라지면 미션으로 돌려보냅니다. 조종기·운용자 명령이 항상 우선합니다.")
            }

            Caption { text: qsTr("기체 간 거리 (지금 / 최소 기록)"); visible: root._run && mlGuard.pairs.length > 0; Layout.topMargin: 4 * u }
            Repeater {
                model: root._run ? mlGuard.pairs : []
                RowLayout {
                    id: pairRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10 * u
                    readonly property color c: modelData.level >= 2 ? MLTheme.warning : (modelData.level === 1 ? MLTheme.caution : MLTheme.text)
                    Text { text: pairRow.modelData.a + " – " + pairRow.modelData.b; color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; Layout.preferredWidth: 90 * u }
                    Text { text: Number(pairRow.modelData.d).toFixed(1) + " m"; color: pairRow.c; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; Layout.preferredWidth: 80 * u }
                    Text { text: "Δz " + Number(pairRow.modelData.dz).toFixed(1); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; Layout.preferredWidth: 70 * u }
                    Text {
                        visible: pairRow.modelData.level > 0
                        text: qsTr("예측 %1 m · %2 s").arg(Number(pairRow.modelData.cpa).toFixed(1)).arg(Number(pairRow.modelData.tcpa).toFixed(0))
                        color: pairRow.c; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: pairRow.modelData.min !== undefined && pairRow.modelData.min !== null ? qsTr("최소 %1 m").arg(Number(pairRow.modelData.min).toFixed(1)) : ""
                        color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
                    }
                }
            }
            Item { Layout.fillHeight: true }
            MLText {
                visible: mlGuard.lastLogFile !== ""
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                color: MLTheme.faint
                font.pixelSize: MLTheme.fsLabel
                text: qsTr("기록: %1").arg(mlGuard.lastLogFile)
            }
        }

        // ================= 사전 점검 =================
        ColumnLayout {
            visible: root.tab === 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8 * u
            RowLayout {
                Layout.fillWidth: true
                MLText { text: qsTr("시동 전 기체별 확인 (일괄 시작 때 다시 확인합니다)"); color: MLTheme.label; font.pixelSize: MLTheme.fsSmall; Layout.fillWidth: true }
                Btn { text: qsTr("다시 점검"); twoStep: false; onClicked: mlGuard.runPreflight() }
            }
            Repeater {
                model: mlGuard.preflight
                Rectangle {
                    id: pfItem
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: pfCol.implicitHeight + 16 * u
                    radius: 6 * u
                    color: "#0D1115"
                    border.color: modelData.ok ? MLTheme.line : "#5A4416"
                    Column {
                        id: pfCol
                        x: 12 * u; y: 8 * u
                        width: parent.width - 24 * u
                        spacing: 3 * u
                        Row {
                            spacing: 10 * u
                            Text { text: pfItem.modelData.id; color: MLTheme.vehicleColor(pfItem.modelData.sysid); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody }
                            MLText { text: pfItem.modelData.ok ? qsTr("이상 없음") : qsTr("확인 필요"); color: pfItem.modelData.ok ? MLTheme.active : MLTheme.caution; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
                        }
                        Repeater {
                            model: pfItem.modelData.issues
                            MLText { required property string modelData; width: pfCol.width; wrapMode: Text.WordWrap; text: "· " + modelData; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }

        // ================= 설정 =================
        Flickable {
            visible: root.tab === 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: setCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { width: 4 * u }
            ColumnLayout {
                id: setCol
                width: parent.width - 8 * u
                spacing: 8 * u

                Caption { text: qsTr("시연 구역 (판단 좌표계 원점 · 전방 방위)") }
                MLText {
                    Layout.fillWidth: true
                    font.pixelSize: MLTheme.fsSmall
                    color: MLTheme.text
                    text: mlGuard.site.lat !== undefined
                          ? qsTr("%1, %2 · 방위 %3°%4").arg(Number(mlGuard.site.lat).toFixed(6)).arg(Number(mlGuard.site.lon).toFixed(6)).arg(Number(mlGuard.site.bearing).toFixed(0)).arg(mlGuard.site.fixed ? "" : qsTr(" (자동)"))
                          : qsTr("미설정 — 기체를 이륙 위치에 기수를 비행 방향으로 놓고 '기수 방향으로 자동'")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * u
                    MLText { text: qsTr("배치"); color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall }
                    Repeater {
                        model: [{k: "hwaseong", t: qsTr("화성 헬리패드 2×2")}, {k: "oregon", t: qsTr("오리건 이륙선")}, {k: "oregon2", t: qsTr("오리건 2")}]
                        Btn {
                            required property var modelData
                            text: modelData.t; tone: "active"; twoStep: false
                            selected: mlGuard.profile === modelData.k
                            available: !root._run; disabledReason: qsTr("가드 정지 상태에서")
                            onClicked: mlGuard.profile = modelData.k
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8 * u
                    MLText { text: qsTr("방위"); color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall }
                    QGCTextField { id: bearingField; Layout.preferredWidth: 70 * u; text: mlGuard.site.bearing !== undefined ? Number(mlGuard.site.bearing).toFixed(0) : "0"; validator: DoubleValidator { bottom: 0; top: 360 } }
                    MLText { text: "°"; color: MLTheme.dim }
                    Item { Layout.fillWidth: true }
                    Btn { text: qsTr("기수 방향으로 자동"); twoStep: false; available: !root._run; disabledReason: qsTr("가드 정지 상태에서"); onClicked: mlGuard.setSiteFromVehicles(-1) }
                    Btn { text: qsTr("입력 방위로 설정"); twoStep: false; available: !root._run; disabledReason: qsTr("가드 정지 상태에서"); onClicked: mlGuard.setSiteFromVehicles(Number(bearingField.text)) }
                    Btn { text: qsTr("지우기"); twoStep: false; available: !root._run; disabledReason: qsTr("가드 정지 상태에서"); onClicked: mlGuard.clearSite() }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: MLTheme.line; Layout.topMargin: 4 * u }
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: qsTr("판단·회피 파라미터 (2대일 때는 원본의 2대 전용 기본값)"); Layout.fillWidth: true }
                    Btn { text: qsTr("기본값 복원"); onClicked: mlGuard.resetParams() }
                }
                Repeater {
                    model: mlGuard.params
                    RowLayout {
                        id: prow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8 * u
                        MLText { text: prow.modelData.group; color: MLTheme.faint; font.pixelSize: MLTheme.fsLabel; Layout.preferredWidth: 44 * u }
                        MLText { text: prow.modelData.label; color: prow.modelData.changed ? MLTheme.target : MLTheme.label; font.pixelSize: MLTheme.fsSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                        QGCTextField {
                            Layout.preferredWidth: 80 * u
                            text: Number(prow.modelData.value).toFixed(2)
                            validator: DoubleValidator { bottom: prow.modelData.min; top: prow.modelData.max }
                            onEditingFinished: { if (Number(text) !== Number(prow.modelData.value)) mlGuard.setParam(prow.modelData.key, Number(text)) }
                        }
                        Text { text: prow.modelData.unit; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; Layout.preferredWidth: 28 * u }
                        Text { text: qsTr("기본 %1").arg(Number(prow.modelData["default"]).toFixed(2)); color: MLTheme.faint; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; Layout.preferredWidth: 70 * u }
                    }
                }
            }
        }

        // ================= 지원 범위 =================
        ColumnLayout {
            visible: root.tab === 3
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8 * u
            MLText { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: MLTheme.text; font.pixelSize: MLTheme.fsSmall; text: mlGuard.supportScope }
            MLText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall
                text: qsTr("판단 로직은 원본 ACACT Guard(core.py)를 C++로 옮긴 것이며, 빌드할 때마다 원본 시뮬레이터 기록과 판단이 같은지 자동 비교합니다.\n\nGCS 를 닫으면 가드가 회피 중이던 기체는 HOLD 로 전환됩니다. GCS 가 비정상 종료되면 속도 명령이 끊겨 PX4 가 Offboard 상실 페일세이프(COM_OF_LOSS_T 후 Hold)로 들어갑니다 — PX4 파라미터를 원본 set_params.py 값으로 맞춰 두세요.\n\n실기 운용 전 반드시 SITL → 고도 분리 리허설 순서로 확인하세요.")
            }
            Item { Layout.fillHeight: true }
        }
    }
}
