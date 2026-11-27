import QtQuick
import QtQuick3D
import QtQuick3D.Helpers

// ACACT 3D 상황도: vehicles at their real positions and heights (local east-north-up metres
// around the ACACT site, or the first vehicle), height stems to the ground grid, the safety
// sphere (½ D_SAFE), flown tracks (red where ACACT flew), the guard's linear prediction over
// T_LOOK and, for pairs in conflict, the predicted closest-approach points. Drag: orbit · wheel: zoom.
// Everything shown comes from mlGuard (no map tiles needed, works offline).
Rectangle {
    id: root
    signal closeRequested()
    signal detachRequested()
    property bool detachable: true
    readonly property real u: MLTheme.u
    // replay (post-flight analysis): positions in the log's own frame (F forward, R right)
    property bool replay:           false
    property var  replayDrones:     []
    property var  replayTracks:     []
    property real replayCursor:     0
    property real dSafeOverride:    NaN
    readonly property bool _has: typeof mlGuard !== "undefined"
    readonly property var  _drones: replay ? replayDrones : (_has ? mlGuard.drones : [])
    readonly property var  _pairs:  replay ? [] : (_has ? mlGuard.pairs : [])
    readonly property real dSafe: !isNaN(dSafeOverride) ? dSafeOverride : (_has && mlGuard.config.d_safe ? mlGuard.config.d_safe : 10)
    function posOf(d) {
        if (d.f !== undefined && d.f !== null) return Qt.vector3d(d.r, d.alt, -d.f)
        return local(d.lat, d.lon, d.alt)
    }
    function okOf(d) { return (d.f !== undefined && d.f !== null) || (d.lat !== undefined && d.lat !== null) }

    color: MLTheme.panelSolid
    radius: MLTheme.panelRadius
    border.color: MLTheme.glassEdge
    clip: true

    // reference point (fixed once there is one, so the scene does not jump)
    property real lat0: NaN
    property real lon0: NaN
    function ensureRef() {
        if (!isNaN(lat0)) return
        var s = _has ? mlGuard.site : null
        if (s && s.lat !== undefined && s.lat !== null) { lat0 = s.lat; lon0 = s.lon; return }
        for (var i = 0; i < _drones.length; i++) if (_drones[i].lat !== undefined && _drones[i].lat !== null) { lat0 = _drones[i].lat; lon0 = _drones[i].lon; return }
    }
    function local(lat, lon, alt) {
        ensureRef()
        if (isNaN(lat0)) return Qt.vector3d(0, alt, 0)
        var x = (lon - lon0) * Math.cos(lat0 * Math.PI / 180) * 111320
        var z = -(lat - lat0) * 110574
        return Qt.vector3d(x, alt, z)
    }
    readonly property vector3d centroid: {
        root.tracksRev
        var n = 0, x = 0, z = 0
        for (var i = 0; i < _drones.length; i++) if (okOf(_drones[i])) { var p = posOf(_drones[i]); x += p.x; z += p.z; n++ }
        return n ? Qt.vector3d(x / n, 0, z / n) : Qt.vector3d(0, 0, 0)
    }
    function colorOf(id) { var m = /^D(\d+)$/.exec(id); return MLTheme.vehicleColor(m ? Number(m[1]) : 1) }
    function byId(id) { for (var i = 0; i < _drones.length; i++) if (_drones[i].id === id) return _drones[i]; return null }

    // flown tracks, 2 Hz (replay: the log's tracks up to the cursor)
    property var tracks: ({})
    onReplayCursorChanged: if (replay) _replayTracks()
    function _replayTracks() {
        var out = ({})
        for (var k = 0; k < replayTracks.length; k++) {
            var p = replayTracks[k].points, a = []
            for (var i = 0; i < p.length && p[i][0] <= replayCursor; i++) a.push({ p: Qt.vector3d(p[i][2], p[i][3], -p[i][1]), own: !!p[i][4] })
            out[replayTracks[k].id] = a
        }
        tracks = out
        tracksRev++
    }
    property int tracksRev: 0
    Timer {
        interval: 500; repeat: true; running: root.visible && !root.replay && root._has && mlGuard.active
        onTriggered: {
            for (var i = 0; i < root._drones.length; i++) {
                var d = root._drones[i]
                if (d.lat === undefined || d.lat === null || !d.fresh) continue
                var p = root.local(d.lat, d.lon, d.alt)
                var tr = root.tracks[d.id] || []
                tr.push({ p: p, own: d.own })
                if (tr.length > 1200) tr.splice(0, 100)
                root.tracks[d.id] = tr
            }
            root.tracksRev++
        }
    }

    View3D {
        id: view
        anchors.fill: parent
        environment: SceneEnvironment {
            clearColor: MLTheme.day ? "#DDE3E9" : "#080B0E"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }
        Node {
            id: originNode
            // orbit around the middle of the fleet (follows it smoothly)
            position: root.centroid
            Behavior on position { Vector3dAnimation { duration: 600 } }
            PerspectiveCamera {
                id: cam
                position: Qt.vector3d(0, 45, 85)
                eulerRotation.x: -28
                clipNear: 0.5
                clipFar: 5000
                fieldOfView: 45
            }
        }
        DirectionalLight { eulerRotation.x: -50; eulerRotation.y: -30; brightness: 1.1 }
        DirectionalLight { eulerRotation.x: -20; eulerRotation.y: 150; brightness: 0.4 }

        // ground grid 300 × 300 m, 10 m cells, 50 m major lines
        Model {
            geometry: ProceduralMesh {
                primitiveMode: ProceduralMesh.Lines
                positions: {
                    var p = [], n = 150
                    for (var v = -n; v <= n; v += 10) { p.push(Qt.vector3d(v, 0, -n), Qt.vector3d(v, 0, n), Qt.vector3d(-n, 0, v), Qt.vector3d(n, 0, v)) }
                    return p
                }
            }
            materials: PrincipledMaterial { baseColor: MLTheme.day ? "#9AA6B2" : "#1E2A33"; lighting: PrincipledMaterial.NoLighting }
        }
        Model {
            geometry: ProceduralMesh {
                primitiveMode: ProceduralMesh.Lines
                positions: {
                    var p = [], n = 150
                    for (var v = -n; v <= n; v += 50) { p.push(Qt.vector3d(v, 0.02, -n), Qt.vector3d(v, 0.02, n), Qt.vector3d(-n, 0.02, v), Qt.vector3d(n, 0.02, v)) }
                    return p
                }
            }
            materials: PrincipledMaterial { baseColor: MLTheme.day ? "#6C7A88" : "#35505F"; lighting: PrincipledMaterial.NoLighting }
        }
        // north arrow
        Model {
            geometry: ProceduralMesh { primitiveMode: ProceduralMesh.Lines; positions: [Qt.vector3d(0, 0.05, 0), Qt.vector3d(0, 0.05, -25), Qt.vector3d(0, 0.05, -25), Qt.vector3d(-3, 0.05, -20), Qt.vector3d(0, 0.05, -25), Qt.vector3d(3, 0.05, -20)] }
            materials: PrincipledMaterial { baseColor: MLTheme.brand; lighting: PrincipledMaterial.NoLighting }
        }

        // vehicles
        Repeater3D {
            model: root._drones.length
            Node {
                id: dn
                readonly property var d: index < root._drones.length ? root._drones[index] : ({})
                readonly property bool ok: root.okOf(d)
                readonly property vector3d pos: ok ? root.posOf(d) : Qt.vector3d(0, 0, 0)
                readonly property color col: root.colorOf(d.id)
                visible: ok
                Model {
                    source: "#Sphere"; position: dn.pos; scale: Qt.vector3d(0.018, 0.018, 0.018)
                    materials: PrincipledMaterial { baseColor: dn.d.own ? MLTheme.warning : dn.col; roughness: 0.35 }
                }
                // safety sphere (½ D_SAFE)
                Model {
                    source: "#Sphere"; position: dn.pos; scale: Qt.vector3d(root.dSafe / 100, root.dSafe / 100, root.dSafe / 100)
                    materials: PrincipledMaterial { baseColor: dn.d.own ? MLTheme.warning : dn.col; opacity: 0.12; alphaMode: PrincipledMaterial.Blend; lighting: PrincipledMaterial.NoLighting; cullMode: Material.NoCulling }
                }
                // stem to the ground + ground mark
                Model {
                    geometry: ProceduralMesh { primitiveMode: ProceduralMesh.Lines; positions: [Qt.vector3d(dn.pos.x, 0, dn.pos.z), dn.pos] }
                    materials: PrincipledMaterial { baseColor: dn.col; lighting: PrincipledMaterial.NoLighting; opacity: 0.7; alphaMode: PrincipledMaterial.Blend }
                }
                Model {
                    source: "#Cylinder"; position: Qt.vector3d(dn.pos.x, 0.03, dn.pos.z); scale: Qt.vector3d(0.03, 0.0005, 0.03)
                    materials: PrincipledMaterial { baseColor: dn.col; lighting: PrincipledMaterial.NoLighting; opacity: 0.5; alphaMode: PrincipledMaterial.Blend }
                }
                // prediction over T_LOOK
                Model {
                    visible: !!dn.d.pred && dn.d.pred.length > 1
                    geometry: ProceduralMesh {
                        primitiveMode: ProceduralMesh.Lines
                        positions: {
                            var p = [], pr = dn.d.pred || []
                            for (var i = 1; i < pr.length; i++) p.push(root.local(pr[i - 1][0], pr[i - 1][1], dn.d.alt), root.local(pr[i][0], pr[i][1], dn.d.alt))
                            return p.length ? p : [Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)]
                        }
                    }
                    materials: PrincipledMaterial { baseColor: dn.col; lighting: PrincipledMaterial.NoLighting; opacity: 0.6; alphaMode: PrincipledMaterial.Blend }
                }
                // flown track
                Model {
                    geometry: ProceduralMesh {
                        primitiveMode: ProceduralMesh.Lines
                        positions: {
                            root.tracksRev
                            var t = root.tracks[dn.d.id] || [], p = []
                            for (var i = 1; i < t.length; i++) if (!t[i].own) p.push(t[i - 1].p, t[i].p)
                            return p.length ? p : [Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)]
                        }
                    }
                    materials: PrincipledMaterial { baseColor: dn.col; lighting: PrincipledMaterial.NoLighting }
                }
                Model {
                    geometry: ProceduralMesh {
                        primitiveMode: ProceduralMesh.Lines
                        positions: {
                            root.tracksRev
                            var t = root.tracks[dn.d.id] || [], p = []
                            for (var i = 1; i < t.length; i++) if (t[i].own) p.push(t[i - 1].p, t[i].p)
                            return p.length ? p : [Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)]
                        }
                    }
                    materials: PrincipledMaterial { baseColor: MLTheme.warning; lighting: PrincipledMaterial.NoLighting }
                }
            }
        }
        // predicted closest approach of pairs in conflict
        Repeater3D {
            model: root._pairs.length
            Node {
                id: pn
                readonly property var p: index < root._pairs.length ? root._pairs[index] : ({ level: 0 })
                readonly property var a: root.byId(p.a)
                readonly property var b: root.byId(p.b)
                readonly property bool ok: p.level >= 1 && !!p.cpaA && !!p.cpaB && !!a && !!b
                readonly property vector3d ca: ok ? root.local(p.cpaA[0], p.cpaA[1], a.alt) : Qt.vector3d(0, 0, 0)
                readonly property vector3d cb: ok ? root.local(p.cpaB[0], p.cpaB[1], b.alt) : Qt.vector3d(0, 0, 0)
                visible: ok
                Model {
                    geometry: ProceduralMesh { primitiveMode: ProceduralMesh.Lines; positions: [pn.ca, pn.cb] }
                    materials: PrincipledMaterial { baseColor: MLTheme.riskColor(pn.p.level); lighting: PrincipledMaterial.NoLighting }
                }
                Model { source: "#Sphere"; position: pn.ca; scale: Qt.vector3d(0.01, 0.01, 0.01); materials: PrincipledMaterial { baseColor: MLTheme.riskColor(pn.p.level); lighting: PrincipledMaterial.NoLighting } }
                Model { source: "#Sphere"; position: pn.cb; scale: Qt.vector3d(0.01, 0.01, 0.01); materials: PrincipledMaterial { baseColor: MLTheme.riskColor(pn.p.level); lighting: PrincipledMaterial.NoLighting } }
            }
        }
    }
    OrbitCameraController {
        anchors.fill: view
        origin: originNode
        camera: cam
    }

    // labels (2D over the 3D view)
    Repeater {
        model: root._drones.length
        Rectangle {
            readonly property var d: index < root._drones.length ? root._drones[index] : ({})
            readonly property bool ok: root.okOf(d)
            readonly property var sp: { root.tracksRev; root.replayCursor; cam.position; cam.eulerRotation; originNode.eulerRotation; if (!ok) return Qt.vector3d(-1, -1, -1); var p = root.posOf(d); return view.mapFrom3DScene(Qt.vector3d(p.x, p.y + 2, p.z)) }
            visible: ok && sp.z > 0
            x: sp.x + 8 * root.u; y: sp.y - height - 4 * root.u
            width: lt.implicitWidth + 12 * root.u; height: lt.implicitHeight + 6 * root.u
            radius: 3 * root.u
            color: MLTheme.glass
            border.color: d.own ? MLTheme.warning : root.colorOf(d.id)
            Text { id: lt; anchors.centerIn: parent; text: d.id + "  " + Number(d.alt).toFixed(1) + " m" + (d.own ? "  " + qsTr("회피") : ""); color: d.own ? MLTheme.warning : root.colorOf(d.id); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
        }
    }

    // header
    Rectangle {
        width: parent.width; height: 38 * u
        color: MLTheme.alpha(MLTheme.panelSolid, 0.85)
        Row {
            x: 12 * u; anchors.verticalCenter: parent.verticalCenter; spacing: 10 * u
            MLText { text: root.replay ? qsTr("3D 리플레이") : qsTr("ACACT 3D 상황도"); font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
            MLText { text: root.replay ? qsTr("격자 10 m · 빨간 화살표 = 전방 F (시연 좌표계)") : qsTr("격자 10 m · 굵은 선 50 m · 빨간 화살표 북쪽"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 6 * u; anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * u
            MLIconButton { glyph: "⟲"; tip: qsTr("시점 초기화"); onClicked: { originNode.eulerRotation = Qt.vector3d(0, 0, 0); cam.position = Qt.vector3d(0, 45, 85); cam.eulerRotation = Qt.vector3d(-28, 0, 0) } }
            MLIconButton { glyph: "⌫"; tip: qsTr("궤적 지우기"); onClicked: { root.tracks = ({}); root.tracksRev++ } }
            MLIconButton { visible: root.detachable; glyph: "⧉"; tip: qsTr("새 창으로 분리"); onClicked: root.detachRequested() }
            MLIconButton { glyph: "✕"; tip: qsTr("닫기"); onClicked: root.closeRequested() }
        }
    }
    MLText {
        visible: !root.replay && (!root._has || !mlGuard.active)
        anchors.centerIn: parent
        text: qsTr("ACACT 가드가 실행 중일 때 기체 위치와 경로가 표시됩니다")
        color: MLTheme.dim
    }
}
