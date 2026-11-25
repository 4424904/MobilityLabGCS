// MobilityLab GCS: QGC v5.1.5 FlyView rearranged as a single-screen console.
//
//   ┌ top bar: menu · status · mode · UAV tabs · confirm · indicators · clock ─┐
//   │ 비행 계기 (FMA, PFD,  │ 지도 + QGC 지도 도구 + 목표 조정      │ 추진 · 추세 │
//   │ 핵심 수치, 링크)      │                                       │ 전원 · 경고 │
//   │ MLFlightColumn        ├ 고도 단면 (MLProfile) ────────────────┤ 미션        │
//   ├ 단계 · 명령 · 비상정지 (MLCommandBar) ─────────────────────────────────────┤
//
// The map, QGC's widget layer and the guided value slider live inside the map
// pane. Upstream behaviour (pip video, 3D view, guided actions) is unchanged.
// In full-screen video the console hides and the map pane fills the window.
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Toolbar
import QGroundControl.Viewer3D

import MobilityLab.Controls

Item {
    id: _root

    readonly property bool _is3DMode:       QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D
    readonly property bool _keepSceneAlive: QGroundControl.settingsManager.viewer3DSettings.keepSceneAlive.rawValue

    // These should only be used by MainRootWindow
    property var planController:    _planController
    property var guidedController:  _guidedController

    PlanMasterController {
        id:                     _planController
        flyView:                true
        Component.onCompleted:  start()
    }

    property bool   _mainWindowIsMap:       mapControl.pipState.state === mapControl.pipState.fullState
    property bool   _isFullWindowItemDark:  _mainWindowIsMap ? mapControl.isSatelliteMap : true
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _missionController:     _planController.missionController
    property var    _geoFenceController:    _planController.geoFenceController
    property var    _rallyPointController:  _planController.rallyPointController
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property var    _guidedController:      guidedActionsController
    property var    _guidedValueSlider:     guidedValueSlider
    property var    _widgetLayer:           widgetLayer
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property rect   _centerViewport:        Qt.rect(0, 0, width, height)
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property var    _mapControl:            mapControl
    property real   _widgetMargin:          ScreenTools.defaultFontPixelWidth * 0.75

    // ---- Console layout ----------------------------------------------------
    readonly property bool _consoleVisible: !QGroundControl.videoManager.fullScreen
    readonly property real _u:              MLTheme.u
    readonly property real _leftW:          Math.round(Math.max(340 * _u, Math.min(460 * _u, width * 0.24)))
    readonly property real _rightW:         Math.round(Math.max(330 * _u, Math.min(440 * _u, width * 0.23)))
    readonly property real _profileH:       height > 900 * _u ? 176 * _u : 132 * _u
    readonly property real _gap:            Math.round(ScreenTools.defaultFontPixelWidth * 0.6)

    property real   _fullItemZorder:    0
    property real   _pipItemZorder:     QGroundControl.zOrderWidgets

    function _calcCenterViewPort() {
        var newToolInset = Qt.rect(0, 0, width, height)
        toolstrip.adjustToolInset(newToolInset)
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool();
    }

    QGCToolInsets {
        id:                     _toolInsets
        topEdgeLeftInset:       _consoleVisible ? 0 : toolbar.height
        topEdgeCenterInset:     topEdgeLeftInset
        topEdgeRightInset:      topEdgeLeftInset
        leftEdgeBottomInset:    _pipView.leftEdgeBottomInset
        bottomEdgeLeftInset:    _pipView.bottomEdgeLeftInset
    }

    Rectangle {
        anchors.fill:   parent
        color:          MLTheme.bg
    }

    MLFlightColumn {
        id:                 flightColumn
        anchors.top:        toolbar.bottom
        anchors.bottom:     commandBar.top
        anchors.left:       parent.left
        width:              _leftW
        visible:            _consoleVisible
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
    }

    MLSystemsColumn {
        id:                 systemsColumn
        anchors.top:        toolbar.bottom
        anchors.bottom:     commandBar.top
        anchors.right:      parent.right
        width:              _rightW
        visible:            _consoleVisible
        Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: MLTheme.line }
    }

    MLProfile {
        id:                 profile
        anchors.left:       flightColumn.right
        anchors.right:      systemsColumn.left
        anchors.bottom:     commandBar.top
        height:             _profileH
        visible:            _consoleVisible
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: MLTheme.line }
    }

    MLCommandBar {
        id:                 commandBar
        leftWidth:          _leftW
        rightWidth:         _rightW
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        height:             implicitHeight
        visible:            _consoleVisible
    }

    // Fleet (group) commands, opened from the top bar
    MLFleetPanel {
        id:                 fleetPanel
        anchors.top:        toolbar.bottom
        anchors.left:       flightColumn.right
        anchors.margins:    _gap * 2
        width:              Math.min(520 * _u, mapHolder.width - _gap * 4)
        height:             Math.min(implicitHeight, mapHolder.height - _gap * 4)
        z:                  QGroundControl.zOrderTopMost
        visible:            _consoleVisible && MLState.fleetOpen && QGroundControl.multiVehicleManager.vehicles.count > 1
    }

    // Non-blocking notice when another vehicle connects / disconnects
    MLToast {
        id:                         toast
        anchors.top:                toolbar.bottom
        anchors.topMargin:          _gap * 3
        anchors.horizontalCenter:   mapHolder.horizontalCenter
        z:                          QGroundControl.zOrderTopMost + 1
    }
    Connections {
        target: QGroundControl.multiVehicleManager
        function onVehicleAdded(vehicle) {
            if (QGroundControl.multiVehicleManager.vehicles.count > 1) {
                toast.show(qsTr("UAV %1 연결됨 · 위쪽 탭에서 선택하세요").arg(("0" + vehicle.id).slice(-2)), MLTheme.ok)
            }
        }
        function onVehicleRemoved(vehicle) {
            toast.show(qsTr("UAV %1 연결 끊김").arg(("0" + vehicle.id).slice(-2)), MLTheme.caution)
        }
    }

    // ---- Event log feed: FC messages, mode / arming changes -----------------
    Instantiator {
        model: QGroundControl.multiVehicleManager.vehicles
        delegate: QtObject {
            required property var object
            readonly property var _v: object
            property var _conn: Connections {
                target: _v
                function onTextMessageReceived(sysid, componentid, severity, text, description) {
                    if (severity >= 7) return
                    MLState.log(text, severity <= 3 ? 3 : (severity === 4 ? 2 : 0), sysid, "FC")
                }
                function onFlightModeChanged(mode) { MLState.log(qsTr("비행 모드 → %1").arg(mode), 0, _v.id, "FC") }
                function onArmedChanged(armed) { MLState.log(armed ? qsTr("시동 걸림") : qsTr("시동 꺼짐"), 1, _v.id, "FC") }
            }
            Component.onCompleted: MLState.log(qsTr("UAV %1 연결 · %2").arg(("0" + _v.id).slice(-2)).arg(MLTheme.vehicleTypeName(_v)), 1, _v.id, "GCS")
        }
    }

    Component.onCompleted: mainWindow.criticalVehicleMessageHandler = function(message) { alertBanner.push(message) }
    Component.onDestruction: mainWindow.criticalVehicleMessageHandler = null

    Item {
        id:                 mapHolder
        anchors.top:        _consoleVisible ? toolbar.bottom : parent.top
        anchors.bottom:     _consoleVisible ? profile.top : parent.bottom
        anchors.left:       _consoleVisible ? flightColumn.right : parent.left
        anchors.right:      _consoleVisible ? systemsColumn.left : parent.right
        clip:               true

        FlyViewMap {
            id:                     mapControl
            planMasterController:   _planController
            rightPanelWidth:        ScreenTools.defaultFontPixelHeight * 9
            pipView:                _pipView
            pipMode:                !_mainWindowIsMap
            toolInsets:             customOverlay.totalToolInsets
            mapName:                "FlightDisplayView"
            enabled:                !_is3DMode
            visible:                !_is3DMode
        }

        FlyViewVideo {
            id:         videoControl
            pipView:    _pipView
        }

        PipView {
            id:                     _pipView
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.margins:        _toolsMargin
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  mapControl
            item2:                  QGroundControl.videoManager.hasVideo ? videoControl : null
            show:                   QGroundControl.videoManager.hasVideo && !QGroundControl.videoManager.fullScreen &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState || mapControl.pipState.state === mapControl.pipState.pipState)
            z:                      QGroundControl.zOrderWidgets

            property real leftEdgeBottomInset: visible ? width + anchors.margins : 0
            property real bottomEdgeLeftInset: visible ? height + anchors.margins : 0
        }

        FlyViewWidgetLayer {
            id:                     widgetLayer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            anchors.margins:        _widgetMargin
            anchors.topMargin:      (_consoleVisible ? 0 : toolbar.height) + _widgetMargin
            z:                      _fullItemZorder + 2
            parentToolInsets:       _toolInsets
            mapControl:             _mapControl
            viewer3DCameraController: viewer3DLoader.item ? viewer3DLoader.item.cameraController : null
            visible:                !QGroundControl.videoManager.fullScreen
        }

        FlyViewCustomLayer {
            id:                 customOverlay
            anchors.fill:       widgetLayer
            z:                  _fullItemZorder + 2
            parentToolInsets:   widgetLayer.totalToolInsets
            mapControl:         _mapControl
            visible:            !QGroundControl.videoManager.fullScreen
        }

        // Development tool for visualizing the insets for a paticular layer, show if needed
        FlyViewInsetViewer {
            id:                     widgetLayerInsetViewer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            z:                      widgetLayer.z + 1
            insetsToView:           widgetLayer.totalToolInsets
            visible:                false
        }

        GuidedActionsController {
            id:                 guidedActionsController
            missionController:  _missionController
            guidedValueSlider:     _guidedValueSlider
        }

        //-- Guided value slider (e.g. altitude)
        GuidedValueSlider {
            id:                 guidedValueSlider
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            anchors.topMargin:  _consoleVisible ? 0 : toolbar.height
            z:                  QGroundControl.zOrderTopMost
            visible:            false
        }

        // 목표 조정 (heading / altitude / speed), opened from the command bar
        MLSetpointPanel {
            id:                 setpointPanel
            anchors.left:       parent.left
            anchors.bottom:     parent.bottom
            anchors.margins:    _gap * 2
            z:                  QGroundControl.zOrderTopMost
            visible:            MLState.setpointsOpen || (typeof mlTestSetpoints !== "undefined" && mlTestSetpoints)
            onCloseRequested:   MLState.setpointsOpen = false
        }

        // Critical vehicle messages (replaces QGC's yellow popup)
        MLAlertBanner {
            id:                         alertBanner
            anchors.top:                parent.top
            anchors.topMargin:          _gap * 2
            anchors.horizontalCenter:   parent.horizontalCenter
            width:                      Math.min(720 * _u, parent.width - 360 * _u)
            z:                          QGroundControl.zOrderTopMost
        }

        // Position readout
        MLMapHud {
            anchors.top:            parent.top
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            anchors.margins:        _gap * 2
            z:                      QGroundControl.zOrderWidgets
            visible:                _consoleVisible && !!_activeVehicle && !_is3DMode
        }

        // Corner marks so the map reads as an instrument pane
        Repeater {
            model: 4
            Item {
                required property int index
                readonly property real _len: 14 * _u
                width:  _len; height: _len
                x:      (index % 2 === 0) ? 6 * _u : mapHolder.width - width - 6 * _u
                y:      (index < 2) ? 6 * _u : mapHolder.height - height - 6 * _u
                z:      QGroundControl.zOrderWidgets
                visible: _consoleVisible
                Rectangle { width: parent.width; height: 1.5 * _u; color: "#995BC0EB"; y: index < 2 ? 0 : parent.height - height }
                Rectangle { width: 1.5 * _u; height: parent.height; color: "#995BC0EB"; x: index % 2 === 0 ? 0 : parent.width - width }
            }
        }

        Loader {
            id:           viewer3DLoader
            z:            1
            anchors.fill: parent
            visible:      _is3DMode
        }

        Connections {
            target: QGCViewer3DManager
            function onDisplayModeChanged() {
                if (QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D) {
                    if (!viewer3DLoader.item) {
                        viewer3DLoader.setSource("qrc:/qml/QGroundControl/Viewer3D/Models3D/Viewer3DModel.qml")
                    }
                } else if (!_keepSceneAlive) {
                    viewer3DLoader.source = ""
                }
            }
        }
    }

    FlyViewToolBar {
        id:                 toolbar
        leftWidth:          _leftW
        guidedValueSlider:  _guidedValueSlider
        visible:            !QGroundControl.videoManager.fullScreen
    }
}
