import QtQuick
import QtQuick.Controls

// Operating-mode button in the top bar: shows the current mode; opens a menu of the three modes.
// Choosing a mode only changes what the screen shows (MLState.setUiMode): flight, links, missions
// and ACACT are untouched. SHOWCASE is refused while a real vehicle is connected.
Rectangle {
    id: root
    readonly property real u: MLTheme.u
    readonly property var _modes: [
        { key: "standard", label: "STANDARD", sub: qsTr("기본 운용"), key2: "F1",
          d: qsTr("지도 중심. 기체 연결 · 비행 준비 · 핵심 비행 정보와 경고만. 상세 정보는 펼쳐서 확인.") },
        { key: "advanced", label: "ADVANCED", sub: qsTr("전문 관제"), key2: "F2",
          d: qsTr("모든 패널. 다기체 관제, ACACT 콘솔, 상세 텔레메트리, 비행 분석, 패널 배치 자유.") },
        { key: "showcase", label: "SHOWCASE", sub: qsTr("기술 시연"), key2: "F3",
          d: qsTr("발표용 전체 화면 3D. 데모 또는 비행 기록만 재생하며 조작 버튼이 없음. 실기체 연결 중에는 쓸 수 없음.") }
    ]
    readonly property var _cur: MLState.isShowcase ? _modes[2] : (MLState.isAdvanced ? _modes[1] : _modes[0])
    readonly property color _tone: MLState.isShowcase ? MLTheme.demo : (MLState.isAdvanced ? MLTheme.accent : MLTheme.active)

    implicitWidth:  curRow.implicitWidth + 26 * u
    implicitHeight: 36 * u
    radius:         7 * u
    color:          pop.opened ? MLTheme.alpha(_tone, 0.16) : (ma.containsMouse ? MLTheme.hover : MLTheme.tile)
    border.color:   MLTheme.alpha(_tone, 0.7)

    Row {
        id: curRow
        anchors.centerIn: parent
        spacing: 8 * u
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7 * u; height: width; radius: width / 2; color: root._tone }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: root._cur.label; color: root._tone; font.family: MLTheme.mono; font.pixelSize: 11.5 * u; font.weight: Font.DemiBold; font.letterSpacing: 1.1 * u }
            MLText { text: root._cur.sub; color: MLTheme.dim; font.pixelSize: 10.5 * u }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "▾"; color: MLTheme.dim; font.pixelSize: 12 * u }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pop.opened ? pop.close() : pop.open()
    }
    ToolTip.visible: MLState.helpTips && ma.containsMouse && !pop.opened
    ToolTip.delay: 600
    ToolTip.text: qsTr("화면 모드 — 바꿔도 비행·연결·ACACT 상태는 그대로입니다")

    Popup {
        id: pop
        y: root.height + 8 * u
        x: Math.min(0, -(width - root.width) / 2)
        width: 420 * u
        padding: 8 * u
        background: Rectangle { color: MLTheme.panelSolid; radius: 10 * u; border.color: MLTheme.lineStrong }
        Column {
            width: parent.width
            spacing: 4 * u
            Repeater {
                model: root._modes
                Rectangle {
                    readonly property bool on: MLState.uiMode === modelData.key
                    readonly property color tone: modelData.key === "showcase" ? MLTheme.demo : (modelData.key === "advanced" ? MLTheme.accent : MLTheme.active)
                    readonly property string block: modelData.key === "showcase" ? MLState.showcaseBlockReason() : ""
                    width: parent.width; height: mCol.implicitHeight + 20 * u; radius: 8 * u
                    color: on ? MLTheme.alpha(tone, 0.12) : (iMa.containsMouse ? MLTheme.hover : "transparent")
                    border.color: on ? MLTheme.alpha(tone, 0.8) : "transparent"
                    opacity: block !== "" ? 0.55 : 1
                    Column {
                        id: mCol
                        x: 14 * u; y: 10 * u; width: parent.width - 28 * u
                        spacing: 3 * u
                        Row {
                            spacing: 10 * u
                            Text { text: modelData.label; color: parent.parent.parent.tone; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; font.letterSpacing: 1.1 * u }
                            MLText { text: modelData.sub; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
                            MLText { text: modelData.key2; color: MLTheme.faint; font.pixelSize: MLTheme.fsLabel }
                        }
                        MLText { width: parent.width; text: modelData.d; wrapMode: Text.WordWrap; color: MLTheme.label; font.pixelSize: MLTheme.fsLabel }
                        MLText { visible: parent.parent.block !== ""; width: parent.width; text: parent.parent.block; wrapMode: Text.WordWrap; color: MLTheme.caution; font.pixelSize: MLTheme.fsLabel }
                    }
                    MouseArea { id: iMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { MLState.setUiMode(modelData.key); pop.close() } }
                }
            }
            MLText { x: 14 * u; width: parent.width - 28 * u; text: qsTr("모드를 바꿔도 비행 상태, 연결, 미션, ACACT 제어와 안전 기능은 바뀌지 않습니다."); wrapMode: Text.WordWrap; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; topPadding: 4 * u; bottomPadding: 4 * u }
        }
    }
}
