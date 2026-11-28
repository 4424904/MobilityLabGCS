import QtQuick
import QtQuick.Controls

// The alert centre list (drop-down from the top bar bell).
Popup {
    id: root
    property var center: MLState.alertCenter
    property bool showHistory: false
    Connections { target: MLState; function onTourSet(what, value) { if (what === "alertHistory") root.showHistory = value === "1" } }
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
        // v1.2: current alerts and the history of this session (raised / cleared times)
        Row {
            spacing: 4 * root.u
            MLIconButton { size: 26 * root.u; label: qsTr("현재 %1").arg(root.center ? root.center.alerts.length : 0); checked: !root.showHistory; onClicked: root.showHistory = false }
            MLIconButton { size: 26 * root.u; label: qsTr("이력 %1").arg(root.center ? root.center.history.count : 0); checked: root.showHistory; onClicked: root.showHistory = true }
        }
        ListView {
            visible: root.showHistory
            width: parent.width
            height: Math.min(contentHeight, 560 * root.u)
            clip: true
            model: root.center ? root.center.history : null
            ScrollBar.vertical: ScrollBar {}
            delegate: Row {
                width: ListView.view.width
                spacing: 8 * root.u
                Text { text: model.raised; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; width: 58 * root.u }
                MLText { text: root.center.levelIcons[model.level] + " " + root.center.levelNames[model.level]; color: model.level >= 3 ? MLTheme.warning : (model.level === 2 ? MLTheme.caution : MLTheme.info); font.pixelSize: MLTheme.fsLabel; width: 50 * root.u }
                MLText { text: model.title; color: MLTheme.text; font.pixelSize: MLTheme.fsLabel; width: parent.width - 220 * root.u; elide: Text.ElideRight }
                MLText { text: model.cleared === "" ? qsTr("진행 중") : qsTr("해제 %1").arg(model.cleared); color: model.cleared === "" ? MLTheme.caution : MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
            }
        }
        ListView {
            visible: !root.showHistory
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
                    // level is told by icon and word as well as colour
                    Row {
                        spacing: 6 * root.u
                        Rectangle {
                            width: lvT.implicitWidth + 12 * root.u; height: 18 * root.u; radius: 3 * root.u
                            color: a.level >= 4 ? parent.parent.parent.tone : "transparent"
                            border.color: parent.parent.parent.tone
                            MLText { id: lvT; anchors.centerIn: parent; text: root.center.levelIcons[a.level] + " " + root.center.levelNames[a.level]; color: a.level >= 4 ? "white" : parent.parent.parent.parent.tone; font.pixelSize: MLTheme.fsLabel; font.weight: Font.DemiBold }
                        }
                        MLText { text: a.title; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; color: parent.parent.parent.tone; width: ac.width - 90 * root.u; elide: Text.ElideRight }
                    }
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
