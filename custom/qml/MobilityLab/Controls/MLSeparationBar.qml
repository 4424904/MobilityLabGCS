import QtQuick

// Separation scale for one vehicle pair: 0 … 3 × D_SAFE.
//   red band 0–D_EMERG · amber band D_EMERG–D_SAFE · ● now · ○ predicted minimum (CPA)
Item {
    id: root
    property real now:       NaN
    property real predicted: NaN
    property real dSafe:     10
    property real dEmerg:    5.5
    property int  level:     0
    property bool dimmed:    false
    readonly property real u:     MLTheme.u
    readonly property real range: dSafe * 3
    function px(d) { return Math.max(0, Math.min(1, d / range)) * bar.width }

    height: 30 * u
    opacity: dimmed ? 0.45 : 1

    Item {
        id: bar
        anchors.left: parent.left; anchors.right: parent.right
        y: 6 * u; height: 8 * u
        Rectangle { anchors.fill: parent; radius: 3 * u; color: MLTheme.line }
        Rectangle { x: 0; width: root.px(root.dEmerg); height: parent.height; radius: 3 * u; color: MLTheme.alpha(MLTheme.warning, 0.55) }
        Rectangle { x: root.px(root.dEmerg); width: root.px(root.dSafe) - root.px(root.dEmerg); height: parent.height; color: MLTheme.alpha(MLTheme.caution, 0.45) }
        // predicted minimum
        Rectangle {
            visible: !isNaN(root.predicted)
            x: root.px(root.predicted) - width / 2; anchors.verticalCenter: parent.verticalCenter
            width: 12 * u; height: width; radius: width / 2
            color: MLTheme.panelSolid; border.width: 2; border.color: MLTheme.riskColor(root.level)
            Behavior on x { NumberAnimation { duration: MLTheme.anim } }
        }
        // now
        Rectangle {
            visible: !isNaN(root.now)
            x: root.px(root.now) - width / 2; anchors.verticalCenter: parent.verticalCenter
            width: 12 * u; height: width; radius: width / 2
            color: MLTheme.text; border.width: 2; border.color: MLTheme.panelSolid
            Behavior on x { NumberAnimation { duration: MLTheme.anim } }
        }
        // arrow from now to predicted
        Rectangle {
            visible: !isNaN(root.now) && !isNaN(root.predicted) && Math.abs(root.px(root.now) - root.px(root.predicted)) > 14 * root.u
            x: Math.min(root.px(root.now), root.px(root.predicted)) + 6 * root.u
            width: Math.abs(root.px(root.now) - root.px(root.predicted)) - 12 * root.u
            anchors.verticalCenter: parent.verticalCenter
            height: 2 * root.u
            color: MLTheme.riskColor(root.level)
            opacity: 0.8
        }
    }
    Text { x: root.px(root.dEmerg) - width / 2; y: bar.y + bar.height + 2 * u; text: root.dEmerg.toFixed(1); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: 10.5 * u }
    Text { x: root.px(root.dSafe) - width / 2; y: bar.y + bar.height + 2 * u; text: root.dSafe.toFixed(0); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: 10.5 * u }
    Text { anchors.right: parent.right; y: bar.y + bar.height + 2 * u; text: root.range.toFixed(0) + " m"; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: 10.5 * u }
}
