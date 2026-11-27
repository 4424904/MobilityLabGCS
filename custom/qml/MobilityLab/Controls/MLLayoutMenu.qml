import QtQuick
import QtQuick.Controls

// 화면 구성 menu (top bar): layout presets, which panels / map layers are shown, theme.
// Everything here is saved and restored at the next start (MLState).
Popup {
    id: root
    readonly property real u: MLTheme.u
    padding: 14 * u
    width: 300 * u
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: MLTheme.panelSolid
        radius: MLTheme.panelRadius
        border.color: MLTheme.lineStrong
    }
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: MLTheme.animFast } }
    exit:  Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: MLTheme.animFast } }

    component Toggle: Item {
        id: tg
        property string text
        property bool checked
        signal toggled()
        width: parent.width; height: 32 * MLTheme.u
        MLText { anchors.verticalCenter: parent.verticalCenter; text: tg.text; font.pixelSize: MLTheme.fsSmall }
        Rectangle {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 38 * MLTheme.u; height: 20 * MLTheme.u; radius: height / 2
            color: tg.checked ? MLTheme.accent : MLTheme.lineStrong
            Behavior on color { ColorAnimation { duration: MLTheme.animFast } }
            Rectangle {
                width: 16 * MLTheme.u; height: width; radius: width / 2; y: 2 * MLTheme.u
                x: tg.checked ? parent.width - width - 2 * MLTheme.u : 2 * MLTheme.u
                color: MLTheme.panelSolid
                Behavior on x { NumberAnimation { duration: MLTheme.animFast; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }

    contentItem: Column {
        spacing: 6 * root.u

        MLSectionTitle { text: qsTr("레이아웃") }
        Row {
            spacing: 6 * root.u
            Repeater {
                model: [ { k: "single", t: qsTr("단일 기체") }, { k: "fleet", t: qsTr("다기체") }, { k: "map", t: qsTr("지도 중심") } ]
                Rectangle {
                    readonly property bool on: MLState.layoutPreset === modelData.k
                    width: (root.width - 2 * root.padding - 12 * root.u) / 3; height: 54 * root.u
                    radius: 6 * root.u
                    color: on ? MLTheme.accentSoft : (pm.containsMouse ? MLTheme.hover : MLTheme.tile)
                    border.color: on ? MLTheme.accent : MLTheme.line
                    // mini picture of the layout
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 8 * root.u
                        spacing: 2 * root.u
                        Rectangle { width: modelData.k === "map" ? 0 : 10 * root.u; height: 18 * root.u; radius: 2 * root.u; color: MLTheme.lineStrong; visible: width > 0 }
                        Rectangle { width: modelData.k === "map" ? 44 * root.u : 24 * root.u; height: 18 * root.u; radius: 2 * root.u; color: MLTheme.alpha(MLTheme.accent, 0.35) }
                        Rectangle { width: modelData.k === "map" ? 0 : 10 * root.u; height: 18 * root.u; radius: 2 * root.u; color: modelData.k === "fleet" ? MLTheme.alpha(MLTheme.caution, 0.6) : MLTheme.lineStrong; visible: width > 0 }
                    }
                    MLText { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * root.u; text: modelData.t; font.pixelSize: MLTheme.fsLabel; color: parent.on ? MLTheme.accent : MLTheme.label }
                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: MLState.applyPreset(modelData.k) }
                }
            }
        }

        MLSectionTitle { text: qsTr("표시 항목") }
        Toggle { text: qsTr("왼쪽 패널 (계기 · 편대)"); checked: MLState.leftOpen; onToggled: { MLState.leftOpen = !MLState.leftOpen; MLState.markCustom() } }
        Toggle { text: qsTr("오른쪽 패널 (시스템 · ACACT)"); checked: MLState.rightOpen; onToggled: { MLState.rightOpen = !MLState.rightOpen; MLState.markCustom() } }
        Toggle { text: qsTr("편대 레인"); checked: MLState.dockOpen; onToggled: { MLState.dockOpen = !MLState.dockOpen; MLState.markCustom() } }
        Toggle { text: qsTr("고도 단면"); checked: MLState.profileOpen; onToggled: MLState.profileOpen = !MLState.profileOpen }
        Toggle { text: qsTr("지도 HUD (선택 기체 주요 수치)"); checked: MLState.showVehicleHud; onToggled: MLState.showVehicleHud = !MLState.showVehicleHud }
        Toggle { text: qsTr("위치 정보 (좌표 · MGRS)"); checked: MLState.showPositionHud; onToggled: MLState.showPositionHud = !MLState.showPositionHud }
        Toggle { text: qsTr("비행 궤적"); checked: MLState.showTrails; onToggled: MLState.showTrails = !MLState.showTrails }
        Toggle { text: qsTr("ACACT 예측선 · 최근접점"); checked: MLState.showPredictions; onToggled: MLState.showPredictions = !MLState.showPredictions }

        MLSectionTitle { text: qsTr("테마") }
        Row {
            spacing: 6 * root.u
            Repeater {
                model: [ { day: false, t: qsTr("야간 (실내 · 저조도)") }, { day: true, t: qsTr("주간 (야외 · 직사광)") } ]
                Rectangle {
                    readonly property bool on: MLTheme.day === modelData.day
                    width: (root.width - 2 * root.padding - 6 * root.u) / 2; height: 34 * root.u
                    radius: 6 * root.u
                    color: on ? MLTheme.accentSoft : (tm.containsMouse ? MLTheme.hover : MLTheme.tile)
                    border.color: on ? MLTheme.accent : MLTheme.line
                    MLText { anchors.centerIn: parent; text: modelData.t; font.pixelSize: MLTheme.fsLabel; color: parent.on ? MLTheme.accent : MLTheme.label }
                    MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: MLTheme.setDay(modelData.day) }
                }
            }
        }
    }
}
