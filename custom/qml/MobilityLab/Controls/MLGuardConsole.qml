import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// ACACT 가드 콘솔: everything the guard terminal does, from the GCS.
//
//   실행    에이전트 상태 · 기체 · 프로파일 · [가드 시작] [가드 종료] · 자동 실행
//   준비    방위 · [미션 생성] (plan_gen --from-vehicles) · [파라미터 확인/적용]
//   시나리오 S7_duo … · demo/rehearsal · [불러오기] [시작]
//   진행    [다음 단계 g] [대기 기체만 g!] [재개 r] [자동 진행] [상태 s] [전체 HOLD h]
//   터미널  guard.py 출력 + 직접 입력
//
// The guard runs under guard_agent.py on the guard laptop, which holds its
// stdin; the GCS only types into it. Starting the guard is harmless (it only
// watches), but `start` arms and takes off, so it needs two presses.
Rectangle {
    id: root

    signal closeRequested()

    readonly property real u:       MLTheme.u
    readonly property bool _agent:  typeof mlGuard !== "undefined" && mlGuard.agentFound
    readonly property bool _run:    _agent && mlGuard.agentState === "guard"
    readonly property bool _busy:   _agent && (mlGuard.agentState === "plan" || mlGuard.agentState === "params")
    readonly property bool _link:   typeof mlGuard !== "undefined" && mlGuard.active
    property string drones:         MLState.guardDrones()
    property string scenarioMode:   "demo"

    implicitWidth:  640 * u
    color:          MLTheme.glassStrong
    radius:         MLTheme.panelRadius
    border.color:   MLTheme.glassEdgeHi

    function line(text) {
        if (mlGuard.sendLine(text)) MLState.command(qsTr("가드: %1").arg(text))
        else MLState.log(qsTr("가드 명령 전송 실패: %1").arg(text), 3, 0, "GCS")
    }

    component FieldLabel: MLText { color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.6 * MLTheme.u; Layout.preferredWidth: 64 * MLTheme.u }
    component Btn: MLCommandButton { compact: true; implicitHeight: 32 * MLTheme.u }
    component SectionTitle: MLText {
        color: MLTheme.label; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; font.letterSpacing: 1.2 * MLTheme.u
        Layout.topMargin: 6 * MLTheme.u
    }

    ColumnLayout {
        anchors.fill:       parent
        anchors.margins:    16 * u
        spacing:            8 * u

        // ---- header ---------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 10 * u
            Rectangle {
                width: 8 * u; height: width; radius: width / 2
                color: root._run ? (root._link ? MLTheme.active : MLTheme.caution) : (root._agent ? MLTheme.label : MLTheme.faint)
            }
            MLText { text: qsTr("ACACT 가드"); font.pixelSize: MLTheme.fsValue; font.weight: Font.DemiBold; color: MLTheme.bright }
            MLText {
                Layout.fillWidth: true
                font.pixelSize: MLTheme.fsSmall
                color: MLTheme.dim
                text: !root._agent ? qsTr("에이전트 없음") :
                      root._run ? qsTr("실행 중 · %1 · %2").arg(mlGuard.agentArgs.join(" ")).arg(MLTheme.duration(mlGuard.agentUptime)) :
                      root._busy ? qsTr("%1 실행 중").arg(mlGuard.agentState === "plan" ? "plan_gen" : "set_params") :
                      (mlGuard.local ? qsTr("정지 · GCS 내장 가드") : qsTr("정지 · 에이전트 %1").arg(mlGuard.agentHost))
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

        // no agent: how to get one
        Rectangle {
            visible:            !root._agent
            Layout.fillWidth:   true
            Layout.preferredHeight: noAgent.implicitHeight + 20 * u
            radius:             6 * u
            color:              "#0D1115"
            border.color:       MLTheme.line
            ColumnLayout {
                id: noAgent
                anchors.fill: parent
                anchors.margins: 10 * u
                spacing: 6 * u
                MLText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: MLTheme.fsSmall
                    color: MLTheme.label
                    text: qsTr("가드 노트북(Ubuntu)에서 guard_agent.py 가 실행 중이어야 합니다. install_agent.sh 로 한 번 등록하면 로그인할 때 자동으로 켜집니다. 다른 PC 이면 에이전트를 --allow-lan 으로 실행하세요.")
                }
                RowLayout {
                    spacing: 8 * u
                    FieldLabel { text: qsTr("주소") }
                    QGCTextField {
                        Layout.preferredWidth: 180 * u
                        text: mlGuard.agentAddress
                        placeholderText: qsTr("자동 검색")
                        onEditingFinished: mlGuard.agentAddress = text
                    }
                    Btn {
                        visible: mlGuard.canLaunchLocal
                        text: qsTr("이 PC 에서 에이전트 켜기"); twoStep: false
                        onClicked: mlGuard.launchLocalAgent()
                    }
                }
            }
        }

        // ---- 실행 -------------------------------------------------------------
        SectionTitle { text: qsTr("실행"); visible: root._agent }
        RowLayout {
            visible: root._agent
            Layout.fillWidth: true
            spacing: 8 * u
            FieldLabel { text: qsTr("기체") }
            QGCTextField {
                Layout.preferredWidth: 110 * u
                text: root.drones
                onEditingFinished: root.drones = text.toUpperCase()
            }
            FieldLabel { text: qsTr("프로파일"); Layout.preferredWidth: 52 * u }
            QGCComboBox {
                Layout.preferredWidth: 120 * u
                model: mlGuard.profiles.length ? mlGuard.profiles : ["hwaseong", "oregon", "oregon2"]
                currentIndex: Math.max(0, model.indexOf(mlGuard.profile))
                onActivated: function(index) { mlGuard.profile = model[index] }
            }
            Item { Layout.fillWidth: true }
            Btn {
                visible: !root._run
                text: qsTr("가드 시작"); tone: "go"
                available: !root._busy && root.drones !== ""
                disabledReason: root.drones === "" ? qsTr("연결된 기체가 없습니다") : qsTr("다른 작업이 끝난 뒤에")
                onClicked: { if (mlGuard.startGuard(root.drones)) MLState.command(qsTr("가드 시작 %1 (%2)").arg(root.drones).arg(mlGuard.profile)) }
            }
            Btn {
                visible: root._run
                text: qsTr("가드 종료"); tone: "caution"
                onClicked: { if (mlGuard.stopGuard(false)) MLState.command(qsTr("가드 종료")) }
            }
        }
        RowLayout {
            visible: mlGuard.local
            Layout.fillWidth: true
            spacing: 10 * u
            QGCCheckBox {
                text: qsTr("GCS 가 기체 연결을 가드에 직접 중계 (mavlink-router 불필요)")
                checked: mlGuard.routeVehicles
                onClicked: mlGuard.routeVehicles = checked
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: root._run || root._busy
                text: qsTr("중계 %1기").arg(mlGuard.routedVehicles)
                color: mlGuard.routedVehicles > 0 ? MLTheme.active : MLTheme.caution
                font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
            }
            MLText {
                text: qsTr("폴더 열기"); color: MLTheme.accent; font.pixelSize: MLTheme.fsSmall
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mlGuard.openFolder() }
            }
        }
        QGCCheckBox {
            visible: root._agent
            text: qsTr("기체가 연결되면 가드를 자동으로 시작")
            checked: mlGuard.autoStart
            onClicked: mlGuard.autoStart = checked
        }

        // ---- 준비 -------------------------------------------------------------
        SectionTitle { text: qsTr("준비 (지상)"); visible: root._agent }
        RowLayout {
            visible: root._agent
            Layout.fillWidth: true
            spacing: 8 * u
            FieldLabel { text: qsTr("방위") }
            QGCTextField {
                Layout.preferredWidth: 70 * u
                text: Number(mlGuard.bearing).toFixed(0)
                validator: DoubleValidator { bottom: 0; top: 360 }
                onEditingFinished: mlGuard.bearing = Number(text)
            }
            MLText { text: "°"; color: MLTheme.dim }
            Item { Layout.fillWidth: true }
            Btn {
                text: qsTr("미션 생성"); tone: "active"
                available: !root._run && !root._busy
                disabledReason: qsTr("가드를 끈 상태에서 (기체 홈 위치를 읽습니다)")
                onClicked: { if (mlGuard.runPlan(root.drones)) MLState.command(qsTr("plan_gen %1 · %2 · 방위 %3°").arg(root.drones).arg(mlGuard.profile).arg(Number(mlGuard.bearing).toFixed(0))) }
            }
            Btn {
                text: qsTr("파라미터 확인"); twoStep: false
                available: !root._run && !root._busy
                onClicked: mlGuard.runParams(root.drones, false)
            }
            Btn {
                text: qsTr("파라미터 적용"); tone: "caution"
                available: !root._run && !root._busy
                onClicked: { if (mlGuard.runParams(root.drones, true)) MLState.command(qsTr("set_params --apply %1").arg(root.drones)) }
            }
        }

        // ---- 시나리오 ---------------------------------------------------------
        SectionTitle { text: qsTr("시나리오"); visible: root._agent }
        RowLayout {
            visible: root._agent
            Layout.fillWidth: true
            spacing: 8 * u
            QGCComboBox {
                id: scenCombo
                Layout.fillWidth: true
                textRole: "label"
                model: {
                    var out = []
                    var s = mlGuard.scenarios
                    for (var i = 0; i < s.length; i++) out.push({ name: s[i].name, label: s[i].name + "  ·  " + s[i].title })
                    return out
                }
            }
            Row {
                spacing: 2 * u
                Repeater {
                    model: ["demo", "rehearsal"]
                    Rectangle {
                        required property string modelData
                        width: modeText.implicitWidth + 16 * u; height: 32 * u; radius: 4 * u
                        color: root.scenarioMode === modelData ? MLTheme.panelRaised : "transparent"
                        border.color: root.scenarioMode === modelData ? MLTheme.lineStrong : MLTheme.line
                        Text { id: modeText; anchors.centerIn: parent; text: parent.modelData; color: root.scenarioMode === parent.modelData ? MLTheme.text : MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.scenarioMode = parent.modelData }
                    }
                }
            }
            Btn {
                text: qsTr("불러오기")
                available: root._run && scenCombo.currentIndex >= 0
                disabledReason: qsTr("가드를 먼저 시작하세요")
                onClicked: root.line("load " + scenCombo.model[scenCombo.currentIndex].name + " " + root.scenarioMode)
            }
            Btn {
                text: qsTr("시작 (이륙)"); tone: "go"
                available: root._run
                disabledReason: qsTr("가드를 먼저 시작하세요")
                onClicked: root.line("start")
            }
        }

        // ---- 진행 -------------------------------------------------------------
        SectionTitle { text: qsTr("진행"); visible: root._agent || root._link }
        Flow {
            visible: root._agent || root._link
            Layout.fillWidth: true
            spacing: 6 * u
            readonly property bool _can: root._run || root._link
            Btn { text: qsTr("다음 단계 g"); tone: "go"; available: parent._can; onClicked: root.line("g") }
            Btn { text: qsTr("대기 기체만 g!"); available: parent._can; onClicked: root.line("g!") }
            Btn { text: qsTr("재개 r"); available: parent._can; onClicked: root.line("r") }
            Btn {
                text: mlGuard.autoMode ? qsTr("자동 진행 끄기") : qsTr("자동 진행 켜기")
                tone: "active"; selected: mlGuard.autoMode
                available: parent._can
                onClicked: root.line(mlGuard.autoMode ? "auto off" : "auto on")
            }
            Btn { text: qsTr("상태 s"); twoStep: false; available: root._run; onClicked: root.line("s") }
            Btn { text: qsTr("전체 HOLD h"); tone: "caution"; twoStep: false; available: parent._can; onClicked: root.line("h") }
        }

        // ---- 터미널 -----------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6 * u
            SectionTitle { text: qsTr("터미널"); Layout.topMargin: 0 }
            Item { Layout.fillWidth: true }
            MLText {
                text: qsTr("지우기"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mlGuard.clearConsole() }
            }
        }
        Rectangle {
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            Layout.minimumHeight: 120 * u
            radius:             6 * u
            color:              "#05070A"
            border.color:       MLTheme.line
            ListView {
                id:                 term
                anchors.fill:       parent
                anchors.margins:    8 * u
                clip:               true
                model:              mlGuard.console
                boundsBehavior:     Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { width: 4 * u }
                onCountChanged:     Qt.callLater(positionViewAtEnd)
                delegate: Text {
                    required property string modelData
                    width:          term.width - 8 * MLTheme.u
                    text:           modelData
                    wrapMode:       Text.WrapAnywhere
                    textFormat:     Text.PlainText
                    font.family:    MLTheme.mono
                    font.pixelSize: MLTheme.fsLabel
                    color: modelData.indexOf("※") >= 0 || /오류|실패|Error|Traceback/.test(modelData) ? MLTheme.warning
                         : modelData.indexOf("> ") === 0 ? MLTheme.target
                         : modelData.indexOf("[agent]") === 0 ? MLTheme.dim
                         : /회피|HOLD|경고/.test(modelData) ? MLTheme.caution : "#C9CDD2"
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * u
            Text { text: ">"; color: MLTheme.target; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody }
            QGCTextField {
                id: input
                Layout.fillWidth: true
                enabled: root._run
                placeholderText: root._run ? qsTr("가드 명령 (예: load S7_duo rehearsal)") : qsTr("가드가 실행 중일 때 입력")
                onAccepted: { if (text.trim() !== "") { root.line(text); text = "" } }
            }
        }
    }

    MLPanelChrome { radius: root.radius }
}
