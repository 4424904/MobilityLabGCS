import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Command button for the bottom bar, coloured by tone:
// "normal" (cyan) | "go" (green) | "caution" (amber) | "active" (magenta, RTL) | "danger" (red)
//
// Safety: with `twoStep` (default) the first press only arms the button —
// it lights up and reads "한 번 더 누르면 실행" with a 3 s countdown bar — and
// the command is sent on the second press. Letting the countdown run out
// cancels. This is deliberate rather than an OS double-click, which can
// happen by accident and gives no chance to read what is about to be sent.
Rectangle {
    id: root

    property string text
    property string subText
    property string iconSource
    property string tone:           "normal"
    property string disabledReason
    property bool   available:      true    // not `enabled`, so the tooltip still works when unavailable
    property bool   twoStep:        true
    property int    confirmMs:      3000
    property bool   compact:        false   // smaller variant for panels

    readonly property bool pending: _pending

    signal clicked()

    property bool _pending: false

    readonly property color _toneColor: tone === "go" ? MLTheme.ok
                                       : tone === "caution" ? MLTheme.caution
                                       : tone === "active" ? MLTheme.active
                                       : tone === "danger" ? MLTheme.warning
                                       : MLTheme.accent
    readonly property bool _hover: mouse.containsMouse && available

    function cancel() { _pending = false; countdown.stop() }

    onAvailableChanged: if (!available) cancel()
    onVisibleChanged:   if (!visible) cancel()

    implicitWidth:  Math.max(ScreenTools.defaultFontPixelWidth * (compact ? 9 : 16), content.implicitWidth + ScreenTools.defaultFontPixelWidth * (compact ? 1.6 : 3))
    implicitHeight: ScreenTools.defaultFontPixelHeight * (compact ? 2.5 : 3.2)

    radius:         ScreenTools.defaultFontPixelWidth * 0.5
    color: {
        if (!available)                 return MLTheme.panelRaised
        if (_pending)                   return Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, 0.38)
        if (mouse.pressed)              return Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, 0.30)
        if (_hover)                     return Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, 0.20)
        return Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, 0.10)
    }
    border.width:   _pending ? Math.max(2, ScreenTools.defaultFontPixelWidth * 0.3) : Math.max(1, ScreenTools.defaultFontPixelWidth * 0.18)
    border.color:   available ? _toneColor : MLTheme.line
    opacity:        available ? 1 : 0.4
    clip:           true

    // Pulsing white outline while armed for the second press
    Rectangle {
        anchors.fill:   parent
        visible:        root._pending
        color:          "transparent"
        radius:         root.radius
        border.width:   root.border.width
        border.color:   "white"
        SequentialAnimation on opacity {
            running:    root._pending
            loops:      Animation.Infinite
            NumberAnimation { from: 1; to: 0.1; duration: 300 }
            NumberAnimation { from: 0.1; to: 1; duration: 300 }
        }
    }

    Row {
        id:                 content
        anchors.centerIn:   parent
        spacing:            ScreenTools.defaultFontPixelWidth * 0.9

        QGCColoredImage {
            anchors.verticalCenter: parent.verticalCenter
            visible:        root.iconSource !== ""
            width:          ScreenTools.defaultFontPixelHeight * (root.compact ? 1.0 : 1.5)
            height:         width
            source:         root.iconSource
            color:          root.available ? (root._pending ? "white" : root._toneColor) : MLTheme.dim
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            QGCLabel {
                text:           root.text
                color:          root.available ? (root._pending ? "white" : root._toneColor) : MLTheme.dim
                font.pointSize: root.compact ? ScreenTools.defaultFontPointSize : ScreenTools.mediumFontPointSize
                font.bold:      true
            }
            QGCLabel {
                visible:        (root.subText !== "" && !root.compact) || root._pending
                text:           root._pending ? qsTr("한 번 더 누르면 실행") : root.subText
                color:          root._pending ? "white" : MLTheme.dim
                font.pointSize: ScreenTools.smallFontPointSize
                font.bold:      root._pending
            }
        }
    }

    // Countdown while waiting for the second press
    Rectangle {
        id:             countdownBar
        visible:        root._pending
        anchors.left:   parent.left
        anchors.bottom: parent.bottom
        height:         Math.max(3, ScreenTools.defaultFontPixelHeight * 0.2)
        color:          "white"
        width:          0
    }
    NumberAnimation {
        id:         countdownAnim
        target:     countdownBar
        property:   "width"
        from:       root.width
        to:         0
        duration:   root.confirmMs
    }
    Timer {
        id:             countdown
        interval:       root.confirmMs
        onTriggered:    root._pending = false
    }

    MouseArea {
        id:             mouse
        anchors.fill:   parent
        hoverEnabled:   true
        cursorShape:    root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (!root.available) return
            if (!root.twoStep) { root.clicked(); return }
            if (root._pending) {
                root.cancel()
                root.clicked()
            } else {
                root._pending = true
                countdown.restart()
                countdownAnim.restart()
            }
        }
    }

    ToolTip.visible:    mouse.containsMouse && !root.available && root.disabledReason !== ""
    ToolTip.text:       root.disabledReason
    ToolTip.delay:      400
}
