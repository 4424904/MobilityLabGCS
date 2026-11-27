import QtQuick
import QtQuick.Controls

import QGroundControl

// First-run guide (STANDARD): four steps from launch to flight. Each step shows whether it is
// already done, from live state (a vehicle connected, readiness, a mission on board, flying), so
// the guide follows the operator instead of being a slideshow. Opens once on the first start and
// again from 도움말; "다시 보지 않기" stores MLState.onboardingDone.
Rectangle {
    id: root
    signal closeRequested()
    readonly property real u:       MLTheme.u
    readonly property var  _vs:     QGroundControl.multiVehicleManager.vehicles
    readonly property var  _v:      QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _g:      typeof mlGuard !== "undefined"
    property int _tick: 0
    Timer { interval: 1000; running: root.visible; repeat: true; onTriggered: root._tick++ }

    readonly property var _sum: { _tick; return _v ? MLReadiness.summary(_v, _g ? mlGuard.preflight : [], _g ? mlGuard.missionCheck : ({}), _g) : null }
    readonly property bool _hasMission: { _tick; if (!_sum) return false; for (var i = 0; i < _sum.checks.length; i++) if (_sum.checks[i].key === "mission") return _sum.checks[i].s >= 1; return false }
    readonly property var steps: [
        { n: 1, t: qsTr("기체 연결"), done: _vs.count > 0,
          d: qsTr("기체 전원을 켜고 텔레메트리 모뎀(또는 USB)을 연결합니다. 자동으로 찾아 왼쪽 '비행 준비'에 나타납니다. 여러 대면 위쪽 탭이나 카드를 눌러 명령 대상을 고릅니다."),
          a: qsTr("데모로 연습"), act: function() { MLState.demoOpen = true } },
        { n: 2, t: qsTr("비행 전 점검"), done: !!_sum && _sum.level >= 1,
          d: qsTr("통신·GNSS·배터리·기체 상태·펌웨어·미션·ACACT 7개 항목을 한 화면에서 봅니다. 빨간 항목은 비행 불가 사유이며, 무엇을 하면 되는지 함께 적혀 있습니다."),
          a: qsTr("점검 열기"), act: function() { MLState.preflightOpen = true } },
        { n: 3, t: qsTr("미션 설정"), done: _hasMission,
          d: qsTr("위쪽 메뉴(로고) › 계획에서 경로를 만들고 업로드합니다. 고도·이륙점·다른 기체와의 근접은 자동으로 검사되고, 오류가 있으면 시작이 막힙니다."),
          a: qsTr("계획 화면"), act: function() { mainWindow.showPlanView() } },
        { n: 4, t: qsTr("비행"), done: !!_v && _v.flying,
          d: qsTr("아래 명령 바에서 시동 → 이륙 또는 미션 시작. 모든 명령은 두 번 눌러 실행합니다. 비행 중에는 일시정지·복귀·착륙이 같은 자리에 있고, 비상 정지는 2초 길게 누릅니다."),
          a: "", act: null }
    ]

    width:          Math.min(820 * u, parent ? parent.width - 40 * u : 820 * u)
    height:         content.implicitHeight + 40 * u
    radius:         14 * u
    color:          MLTheme.panelSolid
    border.color:   MLTheme.lineStrong

    Column {
        id: content
        x: 24 * u; y: 20 * u; width: parent.width - 48 * u
        spacing: 16 * u
        Item {
            width: parent.width; height: 44 * u
            Column {
                MLText { text: qsTr("시작하기"); font.pixelSize: MLTheme.fsBig; font.weight: Font.DemiBold }
                MLText { text: qsTr("처음이라면 이 순서대로 진행하세요 · 완료된 단계는 자동으로 표시됩니다"); color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall }
            }
            MLIconButton { anchors.right: parent.right; anchors.top: parent.top; glyph: "✕"; tip: qsTr("닫기"); onClicked: root.closeRequested() }
        }
        Repeater {
            model: root.steps
            Rectangle {
                width: content.width; height: stCol.implicitHeight + 24 * u; radius: 10 * u
                readonly property bool cur: !modelData.done && (index === 0 || root.steps[index - 1].done)
                color: cur ? MLTheme.alpha(MLTheme.accent, 0.08) : MLTheme.tile
                border.color: cur ? MLTheme.accent : (modelData.done ? MLTheme.alpha(MLTheme.active, 0.5) : MLTheme.line)
                Rectangle {
                    x: 14 * u; y: 14 * u; width: 34 * u; height: width; radius: width / 2
                    color: modelData.done ? MLTheme.active : (parent.cur ? MLTheme.accent : MLTheme.panelRaised)
                    Text { anchors.centerIn: parent; text: modelData.done ? "✓" : modelData.n; color: modelData.done || parent.parent.cur ? MLTheme.onAccent : MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.Bold }
                }
                Column {
                    id: stCol
                    x: 62 * u; y: 12 * u; width: parent.width - 62 * u - 150 * u
                    spacing: 4 * u
                    MLText { text: modelData.t + (modelData.done ? qsTr("  · 완료") : ""); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold; color: modelData.done ? MLTheme.active : MLTheme.bright }
                    MLText { width: parent.width; text: modelData.d; wrapMode: Text.WordWrap; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                }
                MLCommandButton {
                    visible: modelData.a !== ""
                    anchors.right: parent.right; anchors.rightMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter
                    compact: true; twoStep: false; text: modelData.a
                    tone: parent.cur ? "active" : "normal"
                    onClicked: if (modelData.act) modelData.act()
                }
            }
        }
        Row {
            spacing: 10 * u
            MLCommandButton { compact: true; twoStep: false; text: qsTr("다시 보지 않기"); onClicked: { MLState.onboardingDone = true; root.closeRequested() } }
            MLText { anchors.verticalCenter: parent.verticalCenter; text: qsTr("위쪽 ⚙ 환경 설정 › 도움말에서 언제든 다시 열 수 있습니다"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
        }
    }
}
