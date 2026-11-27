import QtQuick

import QGroundControl

// Start screen: MOBILITY LAB identity while the console comes up, with the real start-up
// state underneath (nothing here is decorative): settings, the native ACACT engine, the map
// provider, the communication links and the operating mode. Fades out once the console is
// ready (minimum 1.6 s so it can be read), or at a click.
Rectangle {
    id: root
    readonly property real u: MLTheme.u
    color: "#06080A"
    visible: opacity > 0
    z: 100000

    property real _progress: 0
    property bool _ready: false
    readonly property bool _hasGuard: typeof mlGuard !== "undefined"
    readonly property var  _map: QGroundControl.settingsManager.flightMapSettings
    readonly property var  _steps: [
        { t: qsTr("사용자 설정 · 레이아웃 복원"), ok: true, d: MLState.layoutPreset === "fleet" ? qsTr("다기체") : (MLState.layoutPreset === "map" ? qsTr("지도 중심") : qsTr("단일 기체")) },
        { t: qsTr("ACACT 네이티브 엔진 (C++)"), ok: _hasGuard, d: _hasGuard ? qsTr("탑재 · 대기") : qsTr("없음") },
        { t: qsTr("지도 공급자"), ok: !!_map, d: _map ? _map.mapProvider.rawValue + " · " + _map.mapType.rawValue : "—" },
        { t: qsTr("통신 링크 자동 연결"), ok: true, d: qsTr("UDP · 시리얼 감시") },
        { t: qsTr("운용 모드"), ok: true, d: typeof mlDemo !== "undefined" && mlDemo.active ? qsTr("데모 (실기체 명령 차단)") : (_hasGuard && mlGuard.opMode === "field" ? qsTr("실기체 운용") : qsTr("SITL · 시험")) }
    ]

    NumberAnimation on _progress { from: 0; to: 1; duration: 1500; easing.type: Easing.InOutCubic; running: true; onFinished: root._ready = true }
    on_ReadyChanged: if (_ready) fade.start()
    NumberAnimation { id: fade; target: root; property: "opacity"; to: 0; duration: 450; easing.type: Easing.InCubic; onFinished: MLState.bootDone = true }
    MouseArea { anchors.fill: parent; onClicked: fade.start() }

    // faint grid and a red horizon line: instrument-panel feel without decoration for its own sake
    Canvas {
        anchors.fill: parent
        opacity: 0.5
        onPaint: {
            var c = getContext("2d"); c.reset()
            c.strokeStyle = "#11171C"; c.lineWidth = 1
            var g = 48 * root.u
            for (var x = 0; x < width; x += g) { c.beginPath(); c.moveTo(x + 0.5, 0); c.lineTo(x + 0.5, height); c.stroke() }
            for (var y = 0; y < height; y += g) { c.beginPath(); c.moveTo(0, y + 0.5); c.lineTo(width, y + 0.5); c.stroke() }
        }
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -40 * u
        width: parent.width; height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: "#80D80E18" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20 * u
        spacing: 18 * u

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "/MobilityLab/logo.svg"
            sourceSize.height: 120 * u
            fillMode: Image.PreserveAspectFit
            opacity: Math.min(1, root._progress * 3)
            scale: 0.94 + 0.06 * Math.min(1, root._progress * 2)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "MOBILITY LAB"
            color: "#F2F2F0"
            font.family: MLTheme.sans
            font.pixelSize: 34 * u
            font.weight: Font.DemiBold
            font.letterSpacing: 9 * u
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12 * u
            Text { text: "GROUND CONTROL STATION"; color: "#A9B0B8"; font.family: MLTheme.mono; font.pixelSize: 13 * u; font.letterSpacing: 3 * u; anchors.verticalCenter: parent.verticalCenter }
            Rectangle { width: 1; height: 14 * u; color: "#3A434C"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "v" + (typeof mlVersion !== "undefined" ? mlVersion : ""); color: "#D80E18"; font.family: MLTheme.mono; font.pixelSize: 13 * u; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("다기체 자율비행 · ACACT 충돌 회피 관제")
            color: "#7F8892"
            font.family: MLTheme.sans
            font.pixelSize: 14 * u
        }
        Item { width: 1; height: 16 * u }

        // start-up state
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 460 * u
            spacing: 7 * u
            Repeater {
                model: root._steps
                Item {
                    width: parent.width; height: 20 * u
                    readonly property bool shown: root._progress > (index + 0.5) / (root._steps.length + 1)
                    opacity: shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    Text { text: modelData.ok ? "✓" : "!"; color: modelData.ok ? "#6FD394" : "#F5B83A"; font.pixelSize: 13 * u; width: 22 * u; font.family: MLTheme.sans }
                    Text { x: 22 * u; text: modelData.t; color: "#C2C8CF"; font.family: MLTheme.sans; font.pixelSize: 13 * u }
                    Text { anchors.right: parent.right; text: modelData.d; color: "#8E98A2"; font.family: MLTheme.mono; font.pixelSize: 12 * u }
                }
            }
            Item { width: 1; height: 8 * u }
            Rectangle {
                width: parent.width; height: 3 * u; radius: height / 2; color: "#1A2027"
                Rectangle { width: parent.width * root._progress; height: parent.height; radius: parent.radius; color: "#D80E18" }
            }
        }
    }

    Text {
        anchors.bottom: parent.bottom; anchors.bottomMargin: 22 * u
        anchors.horizontalCenter: parent.horizontalCenter
        text: "© MOBILITY LAB Co., Ltd. · Based on QGroundControl (Apache-2.0 / GPLv3)"
        color: "#56606A"
        font.family: MLTheme.sans
        font.pixelSize: 11.5 * u
    }
}
