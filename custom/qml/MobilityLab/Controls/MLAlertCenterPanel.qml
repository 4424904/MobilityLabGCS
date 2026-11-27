import QtQuick
import QtQuick.Controls

// The alert centre list (drop-down from the top bar bell).
Popup {
    id: root
    property var center: MLState.alertCenter
    readonly property real u: MLTheme.u
    width: 440 * u
    padding: 12 * u
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: MLTheme.panelSolid; radius: MLTheme.panelRadius; border.color: MLTheme.lineStrong }
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: MLTheme.animFast } }

    contentItem: Column {
        spacing: 8 * root.u
        Item {
            width: parent.width; height: 30 * root.u
            MLText { anchors.verticalCenter: parent.verticalCenter; text: qsTr("통합 경고 센터"); font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
            MLIconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; label: qsTr("모두 확인"); glyph: "✓"; size: 28 * root.u; enabledState: !!root.center && root.center.unacked > 0; onClicked: root.center.ackAll() }
        }
        MLText {
            visible: !root.center || root.center.alerts.length === 0
            text: qsTr("현재 경고 없음 — 모든 감시 항목 정상")
            color: MLTheme.active; font.pixelSize: MLTheme.fsSmall
        }
        ListView {
            width: parent.width
            height: Math.min(contentHeight, 560 * root.u)
            spacing: 6 * root.u
            clip: true
            model: root.center ? root.center.alerts.length : 0
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                readonly property var a: root.center.alerts[index]
                readonly property bool isAcked: root.center.acked[a.key] >= a.level
                readonly property color tone: a.level >= 3 ? MLTheme.warning : (a.level === 2 ? MLTheme.caution : MLTheme.info)
                width: ListView.view.width
                height: ac.implicitHeight + 16 * root.u
                radius: 6 * root.u
                color: isAcked ? MLTheme.tile : (a.level >= 3 ? MLTheme.warningFill : (a.level === 2 ? MLTheme.cautionFill : MLTheme.tile))
                border.color: MLTheme.alpha(tone, isAcked ? 0.3 : 0.8)
                opacity: isAcked ? 0.7 : 1
                Rectangle { width: 4 * root.u; height: parent.height - 10 * root.u; y: 5 * root.u; x: 0; radius: 2 * root.u; color: parent.tone }
                Column {
                    id: ac
                    x: 14 * root.u; y: 8 * root.u; width: parent.width - 80 * root.u
                    spacing: 2 * root.u
                    MLText { text: a.title; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; color: parent.parent.tone; width: parent.width }
                    MLText { text: qsTr("원인: ") + a.cause; width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: MLTheme.fsLabel; color: MLTheme.text }
                    MLText { text: qsTr("확인: ") + a.action; width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: MLTheme.fsLabel; color: MLTheme.label }
                }
                MLIconButton {
                    anchors.right: parent.right; anchors.rightMargin: 8 * root.u; anchors.top: parent.top; anchors.topMargin: 8 * root.u
                    visible: !parent.isAcked
                    label: qsTr("확인"); size: 26 * root.u
                    onClicked: root.center.ack(a.key, a.level)
                }
            }
        }
    }
}
