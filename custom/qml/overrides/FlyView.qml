// MobilityLab GCS: QGC v5.1.5 FlyView rearranged as a single-screen console.
//
//   ┌ QGC toolbar ─────────────────────────────────────────────────────────┐
//   │ [비행 계기][추진 계통][전원·연료][항법·통신][경고·알림]   (MLTopBand) │
//   │ ┌ map + QGC map tools / video ──────────────────┐ ┌ 미션 ──────────┐ │
//   │ │                                               │ │ (MLMissionPanel)│ │
//   │ └───────────────────────────────────────────────┘ └────────────────┘ │
//   │ [단계 표시 · 명령 버튼 · 시계 · 비상 정지]            (MLCommandBar) │
//   └──────────────────────────────────────────────────────────────────────┘
//
// Everything below the toolbar is laid out here; the map, QGC's widget layer
// and the guided value slider live inside the map pane. Upstream behaviour
// (pip video, 3D view, guided actions) is unchanged. In full-screen video the
// console panels hide and the map pane fills the window as in QGC.
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
    readonly property real _gap:            Math.round(ScreenTools.defaultFontPixelWidth * 0.6)
    readonly property real _bandHeight:     Math.round(Math.max(ScreenTools.defaultFontPixelHeight * 14.5,
                                                                Math.min(ScreenTools.defaultFontPixelHeight * 27, (height - toolbar.height) * 0.36)))
    readonly property real _sideWidth:      Math.round(Math.max(ScreenTools.defaultFontPixelWidth * 36,
                                                                Math.min(ScreenTools.defaultFontPixelWidth * 54, width * 0.23)))

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

    MLTopBand {
        id:                 topBand
        anchors.top:        parent.top
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.topMargin:  toolbar.height + _gap
        anchors.leftMargin: _gap
        anchors.rightMargin: _gap
        height:             _bandHeight
        visible:            _consoleVisible
    }

    MLCommandBar {
        id:                 commandBar
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        anchors.margins:    _gap
        height:             implicitHeight
        visible:            _consoleVisible
    }

    MLMissionPanel {
        id:                 missionPanel
        anchors.top:        topBand.bottom
        anchors.bottom:     commandBar.top
        anchors.right:      parent.right
        anchors.margins:    _gap
        width:              _sideWidth
        visible:            _consoleVisible
    }

    Item {
        id:                 mapHolder
        anchors.top:        _consoleVisible ? topBand.bottom : parent.top
        anchors.bottom:     _consoleVisible ? commandBar.top : parent.bottom
        anchors.left:       parent.left
        anchors.right:      _consoleVisible ? missionPanel.left : parent.right
        anchors.topMargin:  _consoleVisible ? _gap : 0
        anchors.bottomMargin: _consoleVisible ? _gap : 0
        anchors.leftMargin: _consoleVisible ? _gap : 0
        anchors.rightMargin: _consoleVisible ? _gap : 0
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

        // Thin frame so the map reads as one console pane
        Rectangle {
            anchors.fill:   parent
            z:              QGroundControl.zOrderTopMost
            visible:        _consoleVisible
            color:          "transparent"
            border.color:   MLTheme.line
            border.width:   1
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
        guidedValueSlider:  _guidedValueSlider
        visible:            !QGroundControl.videoManager.fullScreen
    }
}
