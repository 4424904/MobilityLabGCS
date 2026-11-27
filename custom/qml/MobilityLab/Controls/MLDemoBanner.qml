import QtQuick

// Always-visible demo mark over the map while the built-in demo runs, so demo data is never
// mistaken for a real flight.
Rectangle {
    id: root
    readonly property real u: MLTheme.u
    readonly property bool on: typeof mlDemo !== "undefined" && mlDemo.active
    visible: on
    width: row.implicitWidth + 28 * u
    height: 30 * u
    radius: height / 2
    color: MLTheme.alpha(MLTheme.demo, 0.92)
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10 * root.u
        Text { text: "DEMO"; color: "white"; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; font.weight: Font.Bold; font.letterSpacing: 2 * root.u; anchors.verticalCenter: parent.verticalCenter }
        Rectangle { width: 1; height: 14 * root.u; color: "#80FFFFFF"; anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("시뮬레이션 기체 · 실기체 링크 차단됨 · 시험 기록 아님") + (root.on && mlDemo.timeScale !== 1 ? "  ·  " + mlDemo.timeScale + "×" : "")
            color: "white"; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsSmall
        }
    }
}
