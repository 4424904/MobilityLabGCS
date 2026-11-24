import QtQuick

import QGroundControl
import QGroundControl.Controls

// MobilityLab fly view overlay (loaded in place of QGC's FlyViewCustomLayer).
//
//   ┌ toolbar ───────────────────────────────────────────────────────────┐
//   │ tools          [MASTER WARNING][MASTER CAUTION]      ┌ PFD       ┐ │
//   │                       alert list                     │ 기체 상태  │ │
//   │                                                      │ 동력 계통  │ │
//   │                         map                          └───────────┘ │
//   │ video  ┌ 연결─준비─무장─비행─착륙        next step ┐                 │
//   │        └ [context buttons ...]      [비상 정지]   ┘  telemetry (QGC)│
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
    readonly property real _panelWidth: Math.min(ScreenTools.defaultFontPixelWidth * 38, width * 0.3)

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

    // Right column: flight instrument + vehicle status (+ powertrain when reported).
    // Drops below QGC's multi-vehicle panel when that panel is showing.
    readonly property bool _mvPanel: QGroundControl.multiVehicleManager.vehicles.count > 1
                                     && QGroundControl.settingsManager.appSettings.enableMultiVehiclePanel.rawValue

    MLVehiclePanel {
        id:                 systems
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.topMargin:  root._mvPanel ? parentToolInsets.topEdgeRightInset : 0
        width:              root._panelWidth
        height:             Math.min(implicitHeight, root.height - anchors.topMargin - parentToolInsets.bottomEdgeRightInset - root._m)
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
