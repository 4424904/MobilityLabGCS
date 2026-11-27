import QtQuick

// Status chip: short text in a tinted capsule. blink: for states the operator must notice.
Rectangle {
    id: root
    property string text
    property color  tone:   MLTheme.accent
    property bool   blink:  false
    property bool   filled: false
    readonly property real u: MLTheme.u
    width:  t.implicitWidth + 14 * u
    height: 20 * u
    radius: 4 * u
    color:  filled ? tone : MLTheme.alpha(tone, 0.14)
    border.color: MLTheme.alpha(tone, 0.6)
    Text {
        id: t
        anchors.centerIn: parent
        text: root.text
        color: root.filled ? MLTheme.onAccent : root.tone
        font.family: MLTheme.sans
        font.pixelSize: MLTheme.fsLabel
        font.weight: Font.DemiBold
    }
    SequentialAnimation on opacity {
        running: root.blink
        loops: Animation.Infinite
        onStopped: root.opacity = 1
        NumberAnimation { to: 0.35; duration: 420 }
        NumberAnimation { to: 1.0; duration: 420 }
    }
}
