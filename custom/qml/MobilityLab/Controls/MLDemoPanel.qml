import QtQuick
import QtQuick.Controls

import QGroundControl

// 데모 모드: choose a scenario, start / stop the built-in simulation, run the automatic
// demonstration (missions → mission check → pre-flight → ACACT → take-off), simulate a link
// loss, change the simulation speed. While the demo runs every real link is closed and refused
// (see MLDemo.h) — the banner over the map says so the whole time.
Rectangle {
    id: root
    signal closeRequested()
    readonly property real u: MLTheme.u
    readonly property bool _has: typeof mlDemo !== "undefined"
    readonly property bool _on: _has && mlDemo.active
    property string pick: "duo"
    property int autoStage: 0          // 0 idle · 1 waiting for vehicles · 2 uploading · 3 checks · 4 flying
    property string autoText: ""
    property string prevOpMode: ""      // the demo runs in SITL mode; the operator's mode comes back at the end

    width: 520 * u
    height: col.implicitHeight + 32 * u
    radius: MLTheme.panelRadius
    color: MLTheme.panelSolid
    border.color: MLTheme.demo
    border.width: 1.5

    // CI / exhibition (MLGCS_DEMO_AUTO=1): run the automatic demonstration as soon as the demo is up
    Connections {
        target: root._has ? mlDemo : null
        function onActiveChanged() {
            if (typeof mlTestAcact !== "undefined" && mlTestAcact) console.log("MLDEMO active " + mlDemo.active + " " + mlDemo.scenario)
            if (mlDemo.active && typeof mlDemoAuto !== "undefined" && mlDemoAuto) { root.autoStage = 1; root.autoText = qsTr("시작…") }
            if (!mlDemo.active) root.autoStage = 0
        }
    }
    Connections {
        target: MLState
        function onDemoAutoRequestedChanged() {
            if (MLState.demoAutoRequested && root._on) { root.autoStage = 1; root.autoText = qsTr("시작…") }
            MLState.demoAutoRequested = false
        }
    }
    // progress into the log (CI)
    onAutoTextChanged: if (typeof mlTestAcact !== "undefined" && mlTestAcact && autoText !== "") console.log("MLDEMO auto | " + autoText)

    function vehicleCount() { return QGroundControl.multiVehicleManager.vehicles.count }
    function allReady(n) {
        var vs = QGroundControl.multiVehicleManager.vehicles
        if (vs.count < n) return false
        for (var i = 0; i < vs.count; i++) { var v = vs.get(i); if (!(v.coordinate.isValid && v.homePosition.isValid && v.initialConnectComplete)) return false }
        return typeof mlGuard !== "undefined" && mlGuard.activeIds.split(",").length >= n
    }
    function nFor(key) { var s = _has ? mlDemo.scenarios : []; for (var i = 0; i < s.length; i++) if (s[i].key === key) return s[i].n; return 1 }

    // automatic demonstration: the same operator workflow as with real aircraft
    Timer {
        interval: 1500; repeat: true
        running: root.autoStage > 0 && root.autoStage < 4
        property int k: 1
        onTriggered: {
            var n = root.nFor(mlDemo.scenario)
            if (root.autoStage === 1) {
                root.autoText = qsTr("기체 연결 · 파라미터 수신 대기 (%1/%2)").arg(root.vehicleCount()).arg(n)
                if (root.allReady(n)) { root.autoStage = 2; k = 1 }
            } else if (root.autoStage === 2) {
                if (mlGuard.busyText !== "") return
                if (k > n) { root.autoStage = 3; return }
                root.autoText = qsTr("D%1 미션 업로드 (사용자 계획 파일)").arg(k)
                if (mlGuard.uploadPlanFile(k, mlDemo.planDir + "/DEMO_" + mlDemo.scenario + "_D" + k + ".plan")) k++
            } else if (root.autoStage === 3) {
                if (mlGuard.busyText !== "") return
                var mc = mlGuard.validateMissions()
                if (mc.errors > 0) { root.autoText = qsTr("미션 검사 오류 %1건 — 시작 차단").arg(mc.errors); root.autoStage = 0; return }
                if (!mlGuard.running) mlGuard.start()
                var pf = mlGuard.runPreflight()
                for (var i = 0; i < pf.length; i++) if (!pf[i].ok) { root.autoText = qsTr("사전 점검 미통과: %1 %2").arg(pf[i].id).arg(pf[i].issues.join(" / ")); root.autoStage = 0; return }
                if (mlGuard.startFlight()) {
                    root.autoText = qsTr("ACACT 감시 중 일괄 이륙 — 충돌 예측 시 자동 회피")
                    root.autoStage = 4
                    MLState.applyPreset(n > 1 ? "fleet" : "single")
                    MLState.acactTimelineOpen = n > 1
                } else {
                    root.autoText = qsTr("일괄 시작 거부 — ACACT 콘솔의 이벤트를 확인하세요")
                    root.autoStage = 0
                }
            }
        }
    }

    Column {
        id: col
        x: 16 * u; y: 16 * u
        width: parent.width - 32 * u
        spacing: 10 * u

        Item {
            width: parent.width; height: 30 * u
            Row {
                spacing: 10 * u; anchors.verticalCenter: parent.verticalCenter
                MLChip { text: "DEMO"; tone: MLTheme.demo; filled: true; anchors.verticalCenter: parent.verticalCenter }
                MLText { text: qsTr("데모 · 시뮬레이션 모드"); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            }
            MLIconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "✕"; tip: qsTr("닫기"); onClicked: root.closeRequested() }
        }
        MLText {
            width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
            color: MLTheme.label; font.pixelSize: MLTheme.fsSmall
            text: qsTr("GCS에 내장된 시뮬레이션 기체로 관제·미션·ACACT 기능을 시연합니다. 기체만 가상이고 GCS와 ACACT 계산은 실제 그대로입니다. 데모 중에는 UDP·시리얼 등 모든 실기체 링크가 닫히고 새 연결도 거부되어, 어떤 명령도 실제 기체로 나가지 않습니다. 데모 비행은 SITL 검증 기록으로 남지 않습니다.")
        }

        // scenarios
        Repeater {
            model: root._has ? mlDemo.scenarios : []
            Rectangle {
                readonly property bool on: (root._on ? mlDemo.scenario : root.pick) === modelData.key
                width: col.width; height: 58 * root.u; radius: 8 * root.u
                color: on ? MLTheme.alpha(MLTheme.demo, 0.12) : (sm.containsMouse && !root._on ? MLTheme.hover : MLTheme.tile)
                border.color: on ? MLTheme.demo : MLTheme.line
                opacity: root._on && !on ? 0.5 : 1
                Column {
                    x: 14 * root.u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 28 * root.u
                    MLText { text: modelData.title; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold; color: parent.parent.on ? MLTheme.demo : MLTheme.text }
                    MLText { text: modelData.text; font.pixelSize: MLTheme.fsLabel; color: MLTheme.dim; width: parent.width }
                }
                MouseArea { id: sm; anchors.fill: parent; enabled: !root._on; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick = modelData.key }
            }
        }

        Row {
            spacing: 8 * u
            MLCommandButton {
                visible: !root._on
                text: qsTr("데모 시작")
                tone: "go"; twoStep: false
                implicitHeight: 40 * root.u
                onClicked: {
                    if (typeof mlGuard !== "undefined" && mlGuard.opMode === "field") { root.prevOpMode = "field"; mlGuard.setOpMode("sim") }
                    if (mlDemo.start(root.pick)) { root.autoStage = 0; root.autoText = "" }
                }
            }
            MLCommandButton {
                visible: root._on
                text: qsTr("자동 시연 실행")
                tone: "go"; twoStep: false
                available: root.autoStage === 0 || root.autoStage === 4
                implicitHeight: 40 * root.u
                onClicked: { root.autoStage = 1; root.autoText = qsTr("시작…") }
            }
            MLCommandButton {
                visible: root._on
                text: qsTr("데모 종료")
                tone: "caution"; twoStep: true
                implicitHeight: 40 * root.u
                onClicked: {
                    if (typeof mlGuard !== "undefined" && mlGuard.running) mlGuard.stop()
                    mlDemo.stop()
                    if (root.prevOpMode === "field") { mlGuard.setOpMode("field"); root.prevOpMode = "" }
                    root.autoStage = 0; root.autoText = ""
                }
            }
        }
        MLText {
            visible: root.autoText !== ""
            width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
            text: root.autoText; color: root.autoStage === 0 ? MLTheme.caution : MLTheme.demo; font.pixelSize: MLTheme.fsSmall
        }

        // while running: speed, per-vehicle link loss
        Column {
            visible: root._on
            width: parent.width
            spacing: 8 * root.u
            MLSectionTitle { text: qsTr("시뮬레이션 제어") }
            Row {
                spacing: 6 * root.u
                MLText { text: qsTr("속도"); color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall; anchors.verticalCenter: parent.verticalCenter; width: 70 * root.u }
                Repeater {
                    model: [1, 2, 4]
                    MLIconButton { size: 30 * root.u; label: modelData + "×"; checked: root._on && mlDemo.timeScale === modelData; tone: MLTheme.demo; onClicked: mlDemo.timeScale = modelData }
                }
            }
            Row {
                spacing: 6 * root.u
                MLText { text: qsTr("통신 두절"); color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall; anchors.verticalCenter: parent.verticalCenter; width: 70 * root.u }
                Repeater {
                    model: root._on ? mlDemo.vehicles : []
                    MLIconButton {
                        size: 30 * root.u
                        label: "D" + modelData.sysid + (modelData.linkCut ? qsTr(" 복구") : qsTr(" 끊기"))
                        checked: modelData.linkCut
                        tone: MLTheme.warning
                        onClicked: mlDemo.setLinkCut(modelData.sysid, !modelData.linkCut)
                    }
                }
            }
            MLText {
                width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
                text: qsTr("통신 두절은 해당 기체의 송수신을 모두 끊습니다. ACACT가 회피 중이던 기체는 PX4 Offboard 상실 페일세이프(1초)로 정지·HOLD 합니다.")
            }
        }
    }
}
