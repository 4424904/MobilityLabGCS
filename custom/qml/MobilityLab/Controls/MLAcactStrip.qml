import QtQuick
import QtQuick.Controls

// STANDARD mode: ACACT at a glance, over the top of the map.
//   ● 회피 기동 중 · D2      D1 미션 · FC   D2 ACACT 제어          [상세 ▾]
//   ACACT가 제어 중입니다. 위험하면 HOLD 또는 조종기로 개입하세요 — 운용자 조작이 우선합니다.
// State and colours come from MLAcactStatus (the guard's own published phases); the closest
// separation is the guard's value. "상세" opens the full ACACT panel.
Rectangle {
    id: root
    readonly property real u:       MLTheme.u
    readonly property bool _g:      typeof mlGuard !== "undefined"
    readonly property var  st:      MLAcactStatus.evaluate(_g ? mlGuard : null)
    readonly property color tone:   MLAcactStatus.color(st.key)
    readonly property bool  alarm:  st.level >= 3

    implicitWidth:  Math.max(col.implicitWidth, 420 * u) + 150 * u
    implicitHeight: col.implicitHeight + 20 * u
    radius:         MLTheme.panelRadius
    color:          alarm ? MLTheme.warningFill : MLTheme.glassStrong
    border.color:   st.key === "off" ? MLTheme.glassEdge : MLTheme.alpha(tone, 0.8)
    border.width:   alarm ? 2 : 1
    Behavior on color { ColorAnimation { duration: MLTheme.anim } }

    Column {
        id: col
        x: 16 * u; y: 10 * u
        width: root.width - 150 * u
        spacing: 6 * u
        Row {
            spacing: 12 * u
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 12 * u; height: width; radius: width / 2
                color: root.tone
                SequentialAnimation on opacity {
                    running: root.alarm; loops: Animation.Infinite
                    onStopped: parent.opacity = 1
                    NumberAnimation { to: 0.3; duration: 380 } NumberAnimation { to: 1; duration: 380 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ACACT"
                color: MLTheme.dim
                font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 1.2 * u
            }
            MLText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.st.name
                color: root.st.key === "off" ? MLTheme.label : (root.alarm ? MLTheme.warning : MLTheme.bright)
                font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold
            }
            // closest separation (guard value) while running
            Row {
                visible: root._g && mlGuard.active && mlGuard.closest > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4 * u
                MLText { anchors.baseline: dist.baseline; text: qsTr("최근접"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                Text {
                    id: dist
                    text: root._g && mlGuard.active ? mlGuard.closest.toFixed(1) : "—"
                    color: MLTheme.riskColor(root._g ? mlGuard.worstLevel : 0)
                    font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue; font.weight: Font.Medium
                }
                MLText { anchors.baseline: dist.baseline; text: "m"; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
            }
            // per-vehicle control: who has each vehicle right now
            Repeater {
                model: root._g && mlGuard.active ? mlGuard.drones : []
                Rectangle {
                    readonly property var d: modelData
                    readonly property string who: d.phase === "avoid" ? qsTr("ACACT 제어") : (d.phase === "operator" ? qsTr("운용자") : (d.phase === "lost" ? qsTr("두절") : (d.phase === "return" ? qsTr("복귀") : (d.phase === "mission" ? qsTr("미션") : (d.phase === "ground" ? qsTr("지상") : d.mode)))))
                    readonly property color c: d.phase === "avoid" || d.phase === "lost" ? MLTheme.warning : (d.phase === "operator" ? MLTheme.info : (d.phase === "return" ? MLTheme.caution : MLTheme.active))
                    anchors.verticalCenter: parent.verticalCenter
                    width: chipRow.implicitWidth + 16 * u; height: 26 * u; radius: 13 * u
                    color: MLTheme.alpha(c, 0.14)
                    border.color: MLTheme.alpha(c, 0.7)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6 * u
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 4 * u; height: 14 * u; radius: 2 * u; color: MLTheme.vehicleColor(Number(String(d.id).replace("D", ""))) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: d.id; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
                        MLText { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.who; color: parent.parent.c; font.pixelSize: MLTheme.fsSmall }
                    }
                }
            }
        }
        MLText {
            width: col.width
            visible: text !== ""
            text: root.st.action
            wrapMode: Text.WordWrap
            color: root.alarm ? MLTheme.text : MLTheme.label
            font.pixelSize: MLTheme.fsSmall
        }
    }

    MLIconButton {
        anchors.right: parent.right; anchors.rightMargin: 8 * u
        anchors.top: parent.top; anchors.topMargin: 8 * u
        size: 30 * u
        label: MLState.acactDetailOpen ? qsTr("상세 닫기") : qsTr("상세")
        glyph: "≡"
        checked: MLState.acactDetailOpen
        tip: qsTr("ACACT 상세 — 쌍별 이격·예측, 기체별 개입 사유, 타임라인")
        onClicked: MLState.acactDetailOpen = !MLState.acactDetailOpen
    }
}
