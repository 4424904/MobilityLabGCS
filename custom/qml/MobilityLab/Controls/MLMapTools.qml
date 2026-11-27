import QtQuick
import QtQuick.Controls
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Viewer3D

// Map tools of the flight console (fills the visible map area, above the map):
//   top centre   place / coordinate search (decimal, DMS, MGRS, names via OpenStreetMap)
//   right strip  fit all vehicles · centre on selected · follow · test-site favourites ·
//                distance / area measurement · map provider and type · zoom
//   bottom right map server state, with the reason and a one-click alternative when tiles fail
// Map provider / type are QGC's own settings (Settings › 지도 keeps working the same way).
Item {
    id: root
    property var map                     // FlyViewMap
    property real rightInset: 0          // keep clear of widgets on the right edge
    property real topInset:   0

    readonly property real u:       MLTheme.u
    readonly property bool _hasSvc: typeof mlMap !== "undefined"
    readonly property var  _fm:     QGroundControl.settingsManager.flightMapSettings
    readonly property var  _fly:    QGroundControl.settingsManager.flyViewSettings
    readonly property string _type: _fm.mapProvider.rawValue + " " + _fm.mapType.rawValue
    readonly property var  _active: QGroundControl.multiVehicleManager.activeVehicle

    // ---- map server check: at start, on provider/type change, and every 2 min ---------------
    function probe() {
        if (!_hasSvc || !map) return
        var c = map.center
        mlMap.probe(_type, c.isValid ? c.latitude : 37.5, c.isValid ? c.longitude : 127.0, Math.round(map.zoomLevel))
    }
    Timer { id: probeDelay; interval: 1500; onTriggered: root.probe() }
    Timer { interval: 120000; running: true; repeat: true; onTriggered: root.probe() }
    Connections { target: root._fm.mapProvider; function onRawValueChanged() { probeDelay.restart() } }
    Connections { target: root._fm.mapType; function onRawValueChanged() { probeDelay.restart() } }
    Component.onCompleted: probeDelay.start()

    function setMap(provider, type) {
        _fm.mapProvider.rawValue = provider
        _fm.mapType.rawValue = type
    }
    function goTo(lat, lon, zoom) {
        if (!map) return
        _fly.keepMapCenteredOnVehicle.rawValue = false
        map.center = QtPositioning.coordinate(lat, lon)
        if (zoom !== undefined && zoom > 0) map.zoomLevel = zoom
    }

    // ================= search ==================================================================
    Rectangle {
        id: searchBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topInset + 10 * u
        width: Math.min(460 * u, parent.width - 220 * u)
        height: 38 * u
        radius: height / 2
        color: MLTheme.glassStrong
        border.color: field.activeFocus ? MLTheme.accent : MLTheme.glassEdge
        visible: root.width > 520 * u
        Text { x: 14 * u; anchors.verticalCenter: parent.verticalCenter; text: "⌕"; color: MLTheme.dim; font.pixelSize: 18 * u }
        TextInput {
            id: field
            x: 36 * u; width: parent.width - 80 * u
            anchors.verticalCenter: parent.verticalCenter
            color: MLTheme.text
            font.family: MLTheme.sans
            font.pixelSize: MLTheme.fsSmall
            clip: true
            selectByMouse: true
            onAccepted: if (root._hasSvc) mlMap.search(text, root.map ? root.map.center.latitude : NaN, root.map ? root.map.center.longitude : NaN)
            Keys.onEscapePressed: { text = ""; if (root._hasSvc) mlMap.clearSearch(); focus = false }
            Text {
                visible: !field.text && !field.activeFocus
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("장소 · 주소 · 좌표(위도, 경도 / MGRS) 검색")
                color: MLTheme.dim
                font: field.font
            }
        }
        MLWaitIndicator { anchors.right: parent.right; anchors.rightMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter; visible: root._hasSvc && mlMap.searching; scale: 0.6 }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter
            visible: field.text !== "" && !(root._hasSvc && mlMap.searching)
            text: "✕"; color: MLTheme.dim; font.pixelSize: 14 * u
            MouseArea { anchors.fill: parent; anchors.margins: -6 * root.u; onClicked: { field.text = ""; if (root._hasSvc) mlMap.clearSearch() } }
        }
    }
    Rectangle {
        id: results
        anchors.top: searchBox.bottom; anchors.topMargin: 6 * u
        anchors.horizontalCenter: searchBox.horizontalCenter
        width: searchBox.width
        visible: root._hasSvc && (mlMap.results.length > 0 || mlMap.searchError !== "")
        height: resCol.implicitHeight + 12 * u
        radius: 10 * u
        color: MLTheme.panelSolid
        border.color: MLTheme.lineStrong
        z: 10
        Column {
            id: resCol
            x: 6 * u; y: 6 * u; width: parent.width - 12 * u
            MLText { visible: root._hasSvc && mlMap.searchError !== ""; text: root._hasSvc ? mlMap.searchError : ""; color: MLTheme.caution; font.pixelSize: MLTheme.fsSmall; width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; padding: 8 * root.u }
            Repeater {
                model: root._hasSvc ? mlMap.results : []
                Rectangle {
                    width: resCol.width; height: 48 * root.u; radius: 6 * root.u
                    color: rm.containsMouse ? MLTheme.hover : "transparent"
                    Column {
                        x: 10 * root.u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 20 * root.u
                        MLText { text: modelData.name; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; width: parent.width }
                        MLText { text: modelData.detail; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; width: parent.width }
                    }
                    MouseArea {
                        id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.goTo(modelData.lat, modelData.lon, Math.max(root.map.zoomLevel, 16)); pin.coordinate = QtPositioning.coordinate(modelData.lat, modelData.lon); pin.label = modelData.name; mlMap.clearSearch(); field.focus = false }
                    }
                }
            }
        }
    }
    // search result pin
    property var pin: MapQuickItem {
        property string label
        visible: coordinate.isValid
        anchorPoint.x: pinBody.width / 2
        anchorPoint.y: pinBody.height
        sourceItem: Column {
            id: pinBody
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: pinText.implicitWidth + 14 * root.u; height: 24 * root.u; radius: 4 * root.u
                color: MLTheme.brand
                Text { id: pinText; anchors.centerIn: parent; text: root.pin.label; color: "white"; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel; font.weight: Font.DemiBold }
            }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2 * root.u; height: 14 * root.u; color: MLTheme.brand }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 8 * root.u; height: width; radius: width / 2; color: MLTheme.brand }
        }
    }

    // ================= tool strip ==============================================================
    Rectangle {
        id: strip
        anchors.right: parent.right
        anchors.rightMargin: root.rightInset + 10 * u
        anchors.verticalCenter: parent.verticalCenter
        width: 46 * u
        height: tools.implicitHeight + 12 * u
        radius: 10 * u
        color: MLTheme.glassStrong
        border.color: MLTheme.glassEdge
        Column {
            id: tools
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6 * u
            spacing: 2 * u
            MLIconButton { size: 38 * root.u; glyph: "⤢"; tip: qsTr("전체 기체 화면 맞춤"); onClicked: MLState.fitAllRequested() }
            MLIconButton { size: 38 * root.u; glyph: "◎"; tip: qsTr("선택 기체로 이동"); enabledState: !!root._active; onClicked: if (root._active) root.goTo(root._active.coordinate.latitude, root._active.coordinate.longitude) }
            MLIconButton {
                size: 38 * root.u; glyph: "⌖"
                tip: checked ? qsTr("기체 추적 중 — 눌러서 해제") : qsTr("선택 기체 추적")
                checked: root._fly.keepMapCenteredOnVehicle.rawValue
                onClicked: root._fly.keepMapCenteredOnVehicle.rawValue = !checked
            }
            Rectangle { width: 30 * root.u; height: 1; color: MLTheme.line; anchors.horizontalCenter: parent.horizontalCenter }
            MLIconButton { id: favBtn; size: 38 * root.u; glyph: "★"; tip: qsTr("비행시험장 즐겨찾기"); checked: favPop.opened; onClicked: favPop.opened ? favPop.close() : favPop.open() }
            MLIconButton { size: 38 * root.u; glyph: "↔"; tip: qsTr("거리 측정"); checked: measure.mode === "distance"; onClicked: measure.toggle("distance") }
            MLIconButton { size: 38 * root.u; glyph: "▱"; tip: qsTr("면적 측정"); checked: measure.mode === "area"; onClicked: measure.toggle("area") }
            Rectangle { width: 30 * root.u; height: 1; color: MLTheme.line; anchors.horizontalCenter: parent.horizontalCenter }
            MLIconButton {
                size: 38 * root.u; glyph: "◭"; tip: qsTr("3D 지도 (건물·고도)로 전환")
                onClicked: {
                    var v3 = QGroundControl.settingsManager.viewer3DSettings
                    if (v3 && !v3.enabled.rawValue) v3.enabled.rawValue = true
                    QGCViewer3DManager.setDisplayMode(QGCViewer3DManager.View3D)
                }
            }
            MLIconButton { id: layerBtn; size: 38 * root.u; glyph: "◫"; tip: qsTr("지도 공급자 · 유형"); checked: layerPop.opened; onClicked: layerPop.opened ? layerPop.close() : layerPop.open() }
            MLIconButton { size: 38 * root.u; glyph: "+"; tip: qsTr("확대"); onClicked: if (root.map) root.map.zoomLevel = Math.min(root.map.maximumZoomLevel, root.map.zoomLevel + 1) }
            MLIconButton { size: 38 * root.u; glyph: "−"; tip: qsTr("축소"); onClicked: if (root.map) root.map.zoomLevel = Math.max(root.map.minimumZoomLevel, root.map.zoomLevel - 1) }
        }
    }

    // ---- favourites ----------------------------------------------------------------------------
    Popup {
        id: favPop
        x: strip.x - width - 8 * u
        y: strip.y
        width: 320 * u
        padding: 12 * u
        background: Rectangle { color: MLTheme.panelSolid; radius: MLTheme.panelRadius; border.color: MLTheme.lineStrong }
        contentItem: Column {
            spacing: 6 * root.u
            MLSectionTitle { text: qsTr("비행시험장 즐겨찾기") }
            MLText {
                visible: !root._hasSvc || mlMap.favorites.length === 0
                width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
                text: qsTr("등록된 시험장이 없습니다. 지도를 시험장으로 옮긴 뒤 아래에서 이름을 붙여 등록하세요.")
            }
            Repeater {
                model: root._hasSvc ? mlMap.favorites : []
                Rectangle {
                    width: parent.width; height: 44 * root.u; radius: 6 * root.u
                    color: fm.containsMouse ? MLTheme.hover : MLTheme.tile
                    Column {
                        x: 10 * root.u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 50 * root.u
                        MLText { text: modelData.name; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; width: parent.width }
                        Text { text: Number(modelData.lat).toFixed(5) + ", " + Number(modelData.lon).toFixed(5); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                    }
                    MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.goTo(modelData.lat, modelData.lon, modelData.zoom); favPop.close() } }
                    MLIconButton { anchors.right: parent.right; anchors.rightMargin: 6 * root.u; anchors.verticalCenter: parent.verticalCenter; size: 26 * root.u; glyph: "✕"; tip: qsTr("삭제"); onClicked: mlMap.removeFavorite(index) }
                }
            }
            Rectangle { width: parent.width; height: 1; color: MLTheme.line }
            Row {
                spacing: 6 * root.u
                Rectangle {
                    width: 200 * root.u; height: 32 * root.u; radius: 6 * root.u
                    color: MLTheme.bg; border.color: favName.activeFocus ? MLTheme.accent : MLTheme.line
                    TextInput {
                        id: favName
                        anchors.fill: parent; anchors.leftMargin: 8 * root.u; anchors.rightMargin: 8 * root.u
                        verticalAlignment: TextInput.AlignVCenter
                        color: MLTheme.text; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsSmall; clip: true; selectByMouse: true
                        Text { visible: !favName.text; anchors.verticalCenter: parent.verticalCenter; text: qsTr("시험장 이름"); color: MLTheme.faint; font: favName.font }
                    }
                }
                MLIconButton {
                    label: qsTr("지도 중심 등록"); glyph: "+"; size: 32 * root.u
                    enabledState: root._hasSvc && !!root.map
                    onClicked: { mlMap.addFavorite(favName.text, root.map.center.latitude, root.map.center.longitude, root.map.zoomLevel); favName.text = "" }
                }
            }
        }
    }

    // ---- provider / type -----------------------------------------------------------------------
    Popup {
        id: layerPop
        x: strip.x - width - 8 * u
        y: Math.max(0, strip.y + strip.height - height)
        width: 360 * u
        padding: 12 * u
        background: Rectangle { color: MLTheme.panelSolid; radius: MLTheme.panelRadius; border.color: MLTheme.lineStrong }
        contentItem: Column {
            spacing: 8 * root.u
            MLSectionTitle { text: qsTr("지도 공급자"); detail: root._type }
            Flow {
                width: parent.width; spacing: 6 * root.u
                Repeater {
                    model: QGroundControl.mapEngineManager.mapProviderList
                    Rectangle {
                        readonly property bool on: root._fm.mapProvider.rawValue === modelData
                        width: pt.implicitWidth + 20 * root.u; height: 30 * root.u; radius: 6 * root.u
                        color: on ? MLTheme.accentSoft : (pmm.containsMouse ? MLTheme.hover : MLTheme.tile)
                        border.color: on ? MLTheme.accent : MLTheme.line
                        MLText { id: pt; anchors.centerIn: parent; text: modelData; font.pixelSize: MLTheme.fsSmall; color: parent.on ? MLTheme.accent : MLTheme.text }
                        MouseArea {
                            id: pmm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var types = QGroundControl.mapEngineManager.mapTypeList(modelData)
                                var keep = types.indexOf(root._fm.mapType.rawValue) >= 0 ? root._fm.mapType.rawValue : (types.indexOf("Satellite") >= 0 ? "Satellite" : types[0])
                                root.setMap(modelData, keep)
                            }
                        }
                    }
                }
            }
            MLSectionTitle { text: qsTr("지도 유형") }
            Flow {
                width: parent.width; spacing: 6 * root.u
                Repeater {
                    model: QGroundControl.mapEngineManager.mapTypeList(root._fm.mapProvider.rawValue)
                    Rectangle {
                        readonly property bool on: root._fm.mapType.rawValue === modelData
                        width: tt.implicitWidth + 20 * root.u; height: 30 * root.u; radius: 6 * root.u
                        color: on ? MLTheme.accentSoft : (tmm.containsMouse ? MLTheme.hover : MLTheme.tile)
                        border.color: on ? MLTheme.accent : MLTheme.line
                        MLText { id: tt; anchors.centerIn: parent; text: modelData; font.pixelSize: MLTheme.fsSmall; color: parent.on ? MLTheme.accent : MLTheme.text }
                        MouseArea { id: tmm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setMap(root._fm.mapProvider.rawValue, modelData) }
                    }
                }
            }
            MLSectionTitle { text: qsTr("지도 서버 상태") }
            Row {
                spacing: 8 * root.u
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 9 * root.u; height: width; radius: width / 2; color: !root._hasSvc ? MLTheme.faint : (mlMap.status === "ok" ? MLTheme.active : (mlMap.status === "error" ? MLTheme.warning : MLTheme.caution)) }
                MLText { width: 290 * root.u; wrapMode: Text.WordWrap; elide: Text.ElideNone; text: root._hasSvc ? (mlMap.statusText || qsTr("확인 전")) : "—"; font.pixelSize: MLTheme.fsSmall }
            }
            Row {
                spacing: 6 * root.u
                MLIconButton { label: qsTr("다시 확인"); glyph: "↻"; size: 30 * root.u; onClicked: root.probe() }
                MLIconButton { label: qsTr("오프라인 지도 관리"); glyph: "⇩"; size: 30 * root.u; onClicked: { layerPop.close(); mainWindow.showSettingsTool("Maps") } }
            }
        }
    }

    // ---- map server state (bottom right; errors stay until fixed) ---------------------------------
    Rectangle {
        id: mapState
        readonly property bool err: root._hasSvc && mlMap.status === "error"
        readonly property bool busy: root._hasSvc && mlMap.status === "checking"
        anchors.right: strip.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10 * u
        width: Math.min(err ? 520 * u : stText.implicitWidth + 40 * u, root.width - 40 * u)
        height: stCol.implicitHeight + 16 * u
        radius: 8 * u
        visible: err || busy || okShow.running
        color: err ? MLTheme.warningFill : MLTheme.glassStrong
        border.color: err ? MLTheme.warning : MLTheme.glassEdge
        Timer { id: okShow; interval: 4000 }
        Connections { target: root._hasSvc ? mlMap : null; function onStatusChanged() { if (mlMap.status === "ok") okShow.restart() } }
        Column {
            id: stCol
            x: 12 * u; y: 8 * u; width: parent.width - 24 * u
            spacing: 6 * u
            Row {
                spacing: 8 * root.u
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8 * root.u; height: width; radius: width / 2; color: mapState.err ? MLTheme.warning : (mapState.busy ? MLTheme.caution : MLTheme.active) }
                MLText { id: stText; text: (mapState.err ? qsTr("지도 표시 불가 · ") : "") + (root._hasSvc ? mlMap.statusText : ""); font.pixelSize: MLTheme.fsSmall; width: Math.min(implicitWidth, stCol.width - 20 * root.u); wrapMode: Text.WordWrap; elide: Text.ElideNone; color: mapState.err ? MLTheme.text : MLTheme.label }
            }
            Row {
                visible: mapState.err
                spacing: 6 * root.u
                MLText { anchors.verticalCenter: parent.verticalCenter; text: qsTr("대체 지도:"); font.pixelSize: MLTheme.fsLabel; color: MLTheme.dim }
                Repeater {
                    model: [ { p: "Esri", t: "World Satellite" }, { p: "Google", t: "Satellite" }, { p: "Bing", t: "Satellite" } ]
                    MLIconButton {
                        visible: root._fm.mapProvider.rawValue !== modelData.p
                        size: 28 * root.u; label: modelData.p + " " + modelData.t
                        onClicked: root.setMap(modelData.p, modelData.t)
                    }
                }
            }
        }
    }

    // ================= measurement =============================================================
    Item {
        id: measure
        anchors.fill: parent
        property string mode: ""          // distance · area
        property var pts: []
        visible: mode !== ""
        function toggle(m) { mode = (mode === m ? "" : m); pts = []; _sync() }
        function _sync() {
            line.path = mode === "distance" ? pts : []
            poly.path = mode === "area" && pts.length >= 3 ? pts : []
            polyEdge.path = mode === "area" ? pts.concat(pts.length > 2 ? [pts[0]] : []) : []
        }
        readonly property real total: {
            var d = 0
            for (var i = 1; i < pts.length; i++) d += pts[i - 1].distanceTo(pts[i])
            if (mode === "area" && pts.length > 2) d += pts[pts.length - 1].distanceTo(pts[0])
            return d
        }
        // spherical polygon area (m²) on a local equirectangular projection — fine for test-site sizes
        readonly property real area: {
            if (mode !== "area" || pts.length < 3) return 0
            var lat0 = pts[0].latitude * Math.PI / 180, R = 6371008.8, a = 0
            var xy = pts.map(function(p) { return [p.longitude * Math.PI / 180 * R * Math.cos(lat0), p.latitude * Math.PI / 180 * R] })
            for (var i = 0; i < xy.length; i++) { var j = (i + 1) % xy.length; a += xy[i][0] * xy[j][1] - xy[j][0] * xy[i][1] }
            return Math.abs(a) / 2
        }
        // click: add a point · drag: pan the map · wheel: zoom · right click: finish
        MouseArea {
            anchors.fill: parent
            cursorShape: drag ? Qt.ClosedHandCursor : Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property bool drag: false
            property real lx
            property real ly
            onPressed: (m) => { drag = false; lx = m.x; ly = m.y }
            onPositionChanged: (m) => {
                if (!pressed) return
                if (!drag && Math.hypot(m.x - lx, m.y - ly) < 6 * root.u) return
                drag = true
                root.map.pan(lx - m.x, ly - m.y)
                lx = m.x; ly = m.y
            }
            onReleased: (m) => {
                if (drag) { drag = false; return }
                if (m.button === Qt.RightButton) { measure.mode = ""; measure.pts = []; measure._sync(); return }
                var p = mapToItem(root.map, m.x, m.y)
                var c = root.map.toCoordinate(Qt.point(p.x, p.y), false)
                if (!c.isValid) return
                var a = measure.pts.slice(); a.push(c); measure.pts = a; measure._sync()
            }
            onWheel: (w) => { root.map.zoomLevel = Math.max(root.map.minimumZoomLevel, Math.min(root.map.maximumZoomLevel, root.map.zoomLevel + w.angleDelta.y / 240)) }
        }
        Rectangle {
            anchors.left: parent.left; anchors.leftMargin: 12 * u
            anchors.bottom: parent.bottom; anchors.bottomMargin: 12 * u
            width: mCol.implicitWidth + 28 * u
            height: mCol.implicitHeight + 20 * u
            radius: 10 * u
            color: MLTheme.glassStrong
            border.color: MLTheme.accent
            Column {
                id: mCol
                x: 14 * u; y: 10 * u
                spacing: 6 * u
                MLText { text: measure.mode === "area" ? qsTr("면적 측정") : qsTr("거리 측정"); font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; color: MLTheme.accent }
                Text {
                    text: {
                        var d = MLTheme.distance(measure.total)
                        if (measure.mode === "area") {
                            var a = measure.area
                            return (a >= 10000 ? (a / 10000).toFixed(2) + " ha" : a.toFixed(0) + " m²") + "   " + qsTr("둘레") + " " + d.v + " " + d.u
                        }
                        return d.v + " " + d.u
                    }
                    color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBig; font.weight: Font.Medium
                }
                MLText { text: measure.pts.length === 0 ? qsTr("지도를 눌러 점을 찍으세요 · 오른쪽 클릭: 끝내기") : qsTr("점 %1개 · 오른쪽 클릭: 끝내기").arg(measure.pts.length); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                Row {
                    spacing: 6 * root.u
                    MLIconButton { label: qsTr("되돌리기"); glyph: "↶"; size: 28 * root.u; enabledState: measure.pts.length > 0; onClicked: { var a = measure.pts.slice(); a.pop(); measure.pts = a; measure._sync() } }
                    MLIconButton { label: qsTr("지우기"); glyph: "⌫"; size: 28 * root.u; enabledState: measure.pts.length > 0; onClicked: { measure.pts = []; measure._sync() } }
                    MLIconButton { label: qsTr("끝내기"); glyph: "✓"; size: 28 * root.u; onClicked: measure.toggle(measure.mode) }
                }
            }
        }
    }
    property var line: MapPolyline { line.width: 3; line.color: String(MLTheme.accent) }
    property var polyEdge: MapPolyline { line.width: 3; line.color: String(MLTheme.accent) }
    property var poly: MapPolygon { color: String(MLTheme.alpha(MLTheme.accent, 0.18)); border.width: 0 }
    Instantiator {
        model: measure.pts.length
        delegate: MapQuickItem {
            coordinate: measure.pts[index]
            anchorPoint.x: 6 * root.u; anchorPoint.y: 6 * root.u
            sourceItem: Rectangle { width: 12 * root.u; height: width; radius: width / 2; color: MLTheme.panelSolid; border.width: 2; border.color: MLTheme.accent }
        }
        onObjectAdded: (i, o) => { if (root.map) root.map.addMapItem(o) }
        onObjectRemoved: (i, o) => { if (root.map) root.map.removeMapItem(o) }
    }

    onMapChanged: if (map) { map.addMapItem(poly); map.addMapItem(line); map.addMapItem(polyEdge); map.addMapItem(pin) }
}
