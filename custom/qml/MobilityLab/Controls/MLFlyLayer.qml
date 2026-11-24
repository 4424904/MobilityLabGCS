import QtQuick

import QGroundControl
import QGroundControl.Controls

// MobilityLab fly view overlay (loaded in place of QGC's FlyViewCustomLayer).
//
//   ┌ toolbar ───────────────────────────────────────────────────────────┐
//   │ tools          [MASTER WARNING][MASTER CAUTION]      ┌ 탠덤 계통 ┐ │
//   │                       alert list                     │ rotors    │ │
//   │                                                      │ engine    │ │
//   │                         map                          │ fuel ...  │ │
//   │ video  [ARM][이륙][미션][일시정지][복귀][착륙][다음 단계][엔진 비상정지] │
//   │                                         telemetry + attitude (QGC)  │
//   └─────────────────────────────────────────────────────────────────────┘
//
// totalToolInsets reports the space these panels take so QGC keeps the
// vehicle and map controls clear of them.
Item {
    id: root

    property var parentToolInsets
    property var totalToolInsets:   _insets
    property var mapControl

    readonly property real _m:          ScreenTools.defaultFontPixelWidth * 0.75
    readonly property real _panelWidth: Math.min(ScreenTools.defaultFontPixelWidth * 36, width * 0.3)

    QGCToolInsets {
        id:                     _insets
        leftEdgeTopInset:       parentToolInsets.leftEdgeTopInset
        leftEdgeCenterInset:    parentToolInsets.leftEdgeCenterInset
        leftEdgeBottomInset:    parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset:      systems.visible ? Math.max(parentToolInsets.rightEdgeTopInset, root.width - systems.x + root._m) : parentToolInsets.rightEdgeTopInset
        rightEdgeCenterInset:   systems.visible ? Math.max(parentToolInsets.rightEdgeCenterInset, root.width - systems.x + root._m) : parentToolInsets.rightEdgeCenterInset
        rightEdgeBottomInset:   parentToolInsets.rightEdgeBottomInset
        topEdgeLeftInset:       parentToolInsets.topEdgeLeftInset
        topEdgeCenterInset:     Math.max(parentToolInsets.topEdgeCenterInset, lamps.y + lamps.height + root._m)
        topEdgeRightInset:      parentToolInsets.topEdgeRightInset
        bottomEdgeLeftInset:    Math.max(parentToolInsets.bottomEdgeLeftInset, root.height - commandBar.y + root._m)
        bottomEdgeCenterInset:  Math.max(parentToolInsets.bottomEdgeCenterInset, root.height - commandBar.y + root._m)
        bottomEdgeRightInset:   parentToolInsets.bottomEdgeRightInset
    }

    // Systems panel: top right, down to QGC's bottom-right instruments.
    // (QGC's own top-right inset is ignored: it reports the hidden multi-vehicle
    // panel's height even when that panel is not shown.)
    MLSystemsPanel {
        id:                 systems
        anchors.right:      parent.right
        anchors.top:        parent.top
        width:              root._panelWidth
        height:             Math.min(implicitHeight, root.height - parentToolInsets.bottomEdgeRightInset - root._m)
    }

    // Master lamps + alert list, centred under the toolbar
    MLMasterLamps {
        id:                         lamps
        anchors.top:                parent.top
        anchors.horizontalCenter:   parent.horizontalCenter
        anchors.horizontalCenterOffset: -(root._panelWidth / 2)
    }

    // Command bar: bottom, between the video inset (left) and QGC's
    // telemetry/attitude instruments (right). Wraps onto two rows if narrow.
    MLCommandBar {
        id:                 commandBar
        anchors.left:       parent.left
        anchors.leftMargin: Math.max(parentToolInsets.leftEdgeBottomInset, 0)
        anchors.bottom:     parent.bottom
        maxWidth:           Math.max(ScreenTools.defaultFontPixelWidth * 40,
                                     root.width - anchors.leftMargin - parentToolInsets.rightEdgeBottomInset - root._m)
    }
}
