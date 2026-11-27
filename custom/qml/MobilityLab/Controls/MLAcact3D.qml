import QtQuick
import QtQuick3D
import QtQuick3D.Helpers

import QGroundControl

// ACACT 3D 상황도 (v1.1)
//
// Vehicles at their real positions and heights (local east-north-up metres around the ACACT site,
// or the first vehicle), drawn as a multicopter or a helicopter model turned to the vehicle's own
// heading, pitch and roll (QGC telemetry). Height stems to the ground, the safety sphere
// (½ D_SAFE: two spheres touching = D_SAFE apart), the flown track (red where ACACT flew), the
// planned mission path from the ACACT mission check (thin, so the avoidance shows as the gap
// between plan and track), the guard's linear prediction over T_LOOK and, for pairs in conflict,
// the predicted closest-approach points.
//
// Sources, never invented:
//   live, guard running   mlGuard.drones / pairs / missionCheck
//   live, guard stopped   QGC vehicles (position, attitude) — no prediction, no risk
//   replay                the guard log (mlAnalysis): positions and ACACT-flown flags; the log has no
//                         attitude, so the model points along its direction of travel (said so on screen)
// The models are enlarged for visibility (×modelScale) — they are symbols, not to scale.
Rectangle {
    id: root
    signal closeRequested()
    signal detachRequested()
    signal fullscreenRequested()
    property bool detachable:       true
    property bool closable:         true
    property bool presentation:     false   // SHOWCASE: bigger labels, slow orbit, no edit buttons
    property bool autoOrbit:        presentation
    readonly property real u: MLTheme.u
    // replay (post-flight analysis): positions in the log's own frame (F forward, R right)
    property bool replay:           false
    property var  replayDrones:     []
    property var  replayTracks:     []
    property real replayCursor:     0
    property real dSafeOverride:    NaN
    property real modelScale:       4

    readonly property bool _has:    typeof mlGuard !== "undefined"
    readonly property bool _guard:  _has && mlGuard.active
    readonly property var  _vs:     QGroundControl.multiVehicleManager.vehicles
    property int _vTick: 0
    Timer { interval: 200; repeat: true; running: root.visible && !root.replay && !root._guard; onTriggered: root._vTick++ }
    // live without the guard: the connected vehicles themselves
    readonly property var _qgcDrones: {
        _vTick
        var out = []
        for (var i = 0; i < _vs.count; i++) {
            var v = _vs.get(i), c = v.coordinate
            if (!c || !c.isValid) continue
            var a = Number(v.altitudeRelative.rawValue)
            out.push({ id: "D" + v.id, sysid: v.id, lat: c.latitude, lon: c.longitude, alt: isNaN(a) ? 0 : a, fresh: !v.vehicleLinkManager.communicationLost, own: false, phase: v.flying ? "other" : "ground" })
        }
        return out
    }
    readonly property var  _drones: replay ? replayDrones : (_guard ? mlGuard.drones : _qgcDrones)
    readonly property var  _pairs:  replay || !_guard ? [] : mlGuard.pairs
    readonly property var  _plans:  replay || !_has || !mlGuard.missionCheck || !mlGuard.missionCheck.vehicles ? [] : mlGuard.missionCheck.vehicles
    readonly property real dSafe: !isNaN(dSafeOverride) ? dSafeOverride : (_has && mlGuard.config.d_safe ? mlGuard.config.d_safe : 10)
    readonly property bool _lowGfx: MLState.gfxQuality === "low" || (MLState.gfxQuality === "auto" && (_drones.length > 4 || width * height > 2600 * 1400))
    readonly property int  _trackMax: _lowGfx ? 300 : 1200

    function sysidOf(d) { if (d.sysid !== undefined) return Number(d.sysid); var m = /^D(\d+)$/.exec(d.id); return m ? Number(m[1]) : 0 }
    function vehicleOf(d) { return replay ? null : QGroundControl.multiVehicleManager.getVehicleById(sysidOf(d)) }
    function isHeli(d) {
        var v = vehicleOf(d)
        return !!v && String(v.vehicleTypeString).toLowerCase().indexOf("helicopter") >= 0
    }
    // attitude in degrees: live from QGC telemetry; replay from the direction of travel (no attitude in the log)
    function attOf(d) {
        root._vTick; root.tracksRev
        var v = vehicleOf(d)
        if (v) {
            var h = Number(v.heading.rawValue), r = Number(v.roll.rawValue), p = Number(v.pitch.rawValue)
            return { h: isNaN(h) ? 0 : h, r: isNaN(r) ? 0 : r, p: isNaN(p) ? 0 : p, real: true }
        }
        var t = tracks[d.id] || []
        if (t.length >= 2) {
            var a = t[t.length - 2].p, b = t[t.length - 1].p
            var dx = b.x - a.x, dz = b.z - a.z
            if (dx * dx + dz * dz > 0.01) return { h: (Math.atan2(dx, -dz) * 180 / Math.PI + 360) % 360, r: 0, p: 0, real: false }
        }
        return { h: 0, r: 0, p: 0, real: false }
    }
    function posOf(d) {
        if (d.f !== undefined && d.f !== null) return Qt.vector3d(d.r, d.alt, -d.f)
        return local(d.lat, d.lon, d.alt)
    }
    function okOf(d) { return (d.f !== undefined && d.f !== null) || (d.lat !== undefined && d.lat !== null) }

    component Key: Row {
        property color c
        property string t
        property bool dash: false
        spacing: 6 * MLTheme.u
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 18 * MLTheme.u; height: dash ? 1 : 3 * MLTheme.u; color: c; opacity: dash ? 0.6 : 1 }
        MLText { text: t; color: MLTheme.label; font.pixelSize: MLTheme.fsLabel }
    }

    color: MLTheme.panelSolid
    radius: presentation ? 0 : MLTheme.panelRadius
    border.color: presentation ? "transparent" : MLTheme.glassEdge
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
    // the reference is fixed outside any binding (writing lat0 inside one would loop)
    on_DronesChanged: ensureRef()
    Component.onCompleted: ensureRef()
    function local(lat, lon, alt) {
        if (isNaN(lat0)) return Qt.vector3d(0, alt, 0)
        var x = (lon - lon0) * Math.cos(lat0 * Math.PI / 180) * 111320
        var z = -(lat - lat0) * 110574
        return Qt.vector3d(x, alt, z)
    }
    readonly property vector3d centroid: {
        root.tracksRev; root._vTick
        var n = 0, x = 0, z = 0
        for (var i = 0; i < _drones.length; i++) if (okOf(_drones[i])) { var p = posOf(_drones[i]); x += p.x; z += p.z; n++ }
        return n ? Qt.vector3d(x / n, 0, z / n) : Qt.vector3d(0, 0, 0)
    }
    function colorOf(id) { var m = /^D(\d+)$/.exec(id); return MLTheme.vehicleColor(m ? Number(m[1]) : 1) }
    function byId(id) { for (var i = 0; i < _drones.length; i++) if (_drones[i].id === id) return _drones[i]; return null }
    function phaseText(d) {
        if (replay) return d.own ? qsTr("ACACT 회피") : ""
        switch (d.phase) {
        case "avoid": return qsTr("ACACT 회피")
        case "return": return qsTr("임무 복귀")
        case "operator": return qsTr("운용자")
        case "lost": return qsTr("두절")
        case "mission": return qsTr("미션")
        case "ground": return qsTr("지상")
        default: return ""
        }
    }

    // flown tracks, 2 Hz (replay: the log's tracks up to the cursor)
    property var tracks: ({})
    onReplayCursorChanged: if (replay) _replayTracks()
    onReplayTracksChanged: if (replay) _replayTracks()
    function _replayTracks() {
        var out = ({})
        for (var k = 0; k < replayTracks.length; k++) {
            var p = replayTracks[k].points, a = []
            for (var i = 0; i < p.length && p[i][0] <= replayCursor; i++) a.push({ p: Qt.vector3d(p[i][2], p[i][3], -p[i][1]), own: !!p[i][4] })
            if (a.length > _trackMax) a = a.slice(a.length - _trackMax)
            out[replayTracks[k].id] = a
        }
        tracks = out
        tracksRev++
    }
    property int tracksRev: 0
    Timer {
        interval: 500; repeat: true; running: root.visible && !root.replay && root._drones.length > 0
        onTriggered: {
            for (var i = 0; i < root._drones.length; i++) {
                var d = root._drones[i]
                if (d.lat === undefined || d.lat === null || d.fresh === false) continue
                var p = root.local(d.lat, d.lon, d.alt)
                var tr = root.tracks[d.id] || []
                tr.push({ p: p, own: !!d.own })
                if (tr.length > root._trackMax) tr.splice(0, tr.length - root._trackMax)
                root.tracks[d.id] = tr
            }
            root.tracksRev++
        }
    }

    View3D {
        id: view
        anchors.fill: parent
        camera: cam
        environment: SceneEnvironment {
            clearColor: MLTheme.day ? "#DCE2E8" : "#06090C"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: root._lowGfx ? SceneEnvironment.NoAA : SceneEnvironment.MSAA
            antialiasingQuality: MLState.gfxQuality === "high" ? SceneEnvironment.VeryHigh : SceneEnvironment.High
        }
        Node {
            id: originNode
            // orbit around the middle of the fleet (follows it smoothly)
            position: root.centroid
            Behavior on position { Vector3dAnimation { duration: 600 } }
            NumberAnimation on eulerRotation.y { running: root.autoOrbit && root.visible; from: 0; to: 360; duration: 90000; loops: Animation.Infinite }
            PerspectiveCamera {
                id: cam
                position: Qt.vector3d(0, 45, 85)
                eulerRotation.x: -28
                clipNear: 0.5
                clipFar: 5000
                fieldOfView: 45
            }
        }
        DirectionalLight { eulerRotation.x: -50; eulerRotation.y: -30; brightness: 1.15 }
        DirectionalLight { eulerRotation.x: -20; eulerRotation.y: 150; brightness: 0.45 }

        // ground: a faint plane and a grid 300 × 300 m, 10 m cells, 50 m major lines
        Model {
            source: "#Rectangle"; eulerRotation.x: -90; position: Qt.vector3d(0, -0.05, 0); scale: Qt.vector3d(3, 3, 1)
            materials: PrincipledMaterial { baseColor: MLTheme.day ? "#E8ECEF" : "#0A1015"; lighting: PrincipledMaterial.NoLighting }
        }
        Model {
            geometry: ProceduralMesh {
                primitiveMode: ProceduralMesh.Lines
                positions: {
                    var p = [], n = 150
                    for (var v = -n; v <= n; v += 10) { p.push(Qt.vector3d(v, 0, -n), Qt.vector3d(v, 0, n), Qt.vector3d(-n, 0, v), Qt.vector3d(n, 0, v)) }
                    return p
                }
            }
            materials: PrincipledMaterial { baseColor: MLTheme.day ? "#B5BFC8" : "#16222B"; lighting: PrincipledMaterial.NoLighting }
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
            materials: PrincipledMaterial { baseColor: MLTheme.day ? "#7D8B98" : "#2E4756"; lighting: PrincipledMaterial.NoLighting }
        }
        // north arrow
        Model {
            geometry: ProceduralMesh { primitiveMode: ProceduralMesh.Lines; positions: [Qt.vector3d(0, 0.05, 0), Qt.vector3d(0, 0.05, -25), Qt.vector3d(0, 0.05, -25), Qt.vector3d(-3, 0.05, -20), Qt.vector3d(0, 0.05, -25), Qt.vector3d(3, 0.05, -20)] }
            materials: PrincipledMaterial { baseColor: MLTheme.brand; lighting: PrincipledMaterial.NoLighting }
        }

        // planned mission paths (ACACT mission check) — thin, in the vehicle colour
        Repeater3D {
            model: root._plans.length
            Model {
                readonly property var pv: index < root._plans.length ? root._plans[index] : ({})
                visible: !!pv.path && pv.path.length > 1
                geometry: ProceduralMesh {
                    primitiveMode: ProceduralMesh.Lines
                    positions: {
                        var p = [], pa = pv.path || []
                        for (var i = 1; i < pa.length; i++) p.push(root.local(pa[i - 1].lat, pa[i - 1].lon, pa[i - 1].alt), root.local(pa[i].lat, pa[i].lon, pa[i].alt))
                        return p.length ? p : [Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)]
                    }
                }
                materials: PrincipledMaterial { baseColor: MLTheme.vehicleColor(pv.sysid || 1); lighting: PrincipledMaterial.NoLighting; opacity: 0.35; alphaMode: PrincipledMaterial.Blend }
            }
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
                readonly property color bodyCol: d.own ? MLTheme.warning : col
                readonly property var att: root.attOf(d)
                readonly property bool heli: root.isHeli(d)
                visible: ok

                // ---- aircraft model, turned to heading / pitch / roll -------------------------
                Node {
                    position: dn.pos
                    eulerRotation: Qt.vector3d(dn.att.p, -dn.att.h, -dn.att.r)
                    scale: Qt.vector3d(root.modelScale, root.modelScale, root.modelScale)
                    // multicopter: body, X arms, four rotor discs, nose cone
                    Node {
                        visible: !dn.heli
                        Model { source: "#Cube"; scale: Qt.vector3d(0.0024, 0.0012, 0.0034); materials: PrincipledMaterial { baseColor: dn.bodyCol; metalness: 0.2; roughness: 0.4 } }
                        Model { source: "#Cube"; eulerRotation.y: 45; scale: Qt.vector3d(0.0075, 0.0005, 0.0006); materials: PrincipledMaterial { baseColor: MLTheme.day ? "#39424B" : "#C9D1D8"; roughness: 0.5 } }
                        Model { source: "#Cube"; eulerRotation.y: -45; scale: Qt.vector3d(0.0075, 0.0005, 0.0006); materials: PrincipledMaterial { baseColor: MLTheme.day ? "#39424B" : "#C9D1D8"; roughness: 0.5 } }
                        Repeater3D {
                            model: [Qt.vector3d(0.265, 0.035, -0.265), Qt.vector3d(-0.265, 0.035, -0.265), Qt.vector3d(0.265, 0.035, 0.265), Qt.vector3d(-0.265, 0.035, 0.265)]
                            Model {
                                source: "#Cylinder"; position: modelData; scale: Qt.vector3d(0.0042, 0.0002, 0.0042)
                                materials: PrincipledMaterial { baseColor: index < 2 ? MLTheme.alpha(dn.bodyCol, 0.55) : (MLTheme.day ? "#55606A" : "#8C99A5"); opacity: 0.7; alphaMode: PrincipledMaterial.Blend; lighting: PrincipledMaterial.NoLighting }
                            }
                        }
                        Model { source: "#Cone"; position: Qt.vector3d(0, 0, -0.24); eulerRotation.x: -90; scale: Qt.vector3d(0.0007, 0.0012, 0.0007); materials: PrincipledMaterial { baseColor: MLTheme.brand; lighting: PrincipledMaterial.NoLighting } }
                    }
                    // helicopter: fuselage, tail boom, main and tail rotor discs, nose mark
                    Node {
                        visible: dn.heli
                        Model { source: "#Sphere"; scale: Qt.vector3d(0.006, 0.0058, 0.0115); materials: PrincipledMaterial { baseColor: dn.bodyCol; metalness: 0.25; roughness: 0.35 } }
                        Model { source: "#Cube"; position: Qt.vector3d(0, 0.06, 0.9); scale: Qt.vector3d(0.0012, 0.0012, 0.012); materials: PrincipledMaterial { baseColor: dn.bodyCol; roughness: 0.4 } }
                        Model { source: "#Cube"; position: Qt.vector3d(0, 0.2, 1.48); scale: Qt.vector3d(0.0006, 0.0034, 0.0024); materials: PrincipledMaterial { baseColor: dn.bodyCol; roughness: 0.4 } }
                        Model { source: "#Cylinder"; position: Qt.vector3d(0, 0.38, 0); scale: Qt.vector3d(0.019, 0.0002, 0.019); materials: PrincipledMaterial { baseColor: MLTheme.day ? "#55606A" : "#9AA6B2"; opacity: 0.45; alphaMode: PrincipledMaterial.Blend; lighting: PrincipledMaterial.NoLighting } }
                        Model { source: "#Cylinder"; position: Qt.vector3d(0.06, 0.24, 1.5); eulerRotation.z: 90; scale: Qt.vector3d(0.0036, 0.0002, 0.0036); materials: PrincipledMaterial { baseColor: MLTheme.day ? "#55606A" : "#9AA6B2"; opacity: 0.55; alphaMode: PrincipledMaterial.Blend; lighting: PrincipledMaterial.NoLighting } }
                        Model { source: "#Cone"; position: Qt.vector3d(0, 0, -0.6); eulerRotation.x: -90; scale: Qt.vector3d(0.0009, 0.0014, 0.0009); materials: PrincipledMaterial { baseColor: MLTheme.brand; lighting: PrincipledMaterial.NoLighting } }
                    }
                }

                // safety sphere (½ D_SAFE: two touching spheres = D_SAFE apart)
                Model {
                    source: "#Sphere"; position: dn.pos; scale: Qt.vector3d(root.dSafe / 100, root.dSafe / 100, root.dSafe / 100)
                    materials: PrincipledMaterial { baseColor: dn.bodyCol; opacity: dn.d.own ? 0.18 : 0.09; alphaMode: PrincipledMaterial.Blend; lighting: PrincipledMaterial.NoLighting; cullMode: Material.NoCulling }
                }
                // stem to the ground + ground ring
                Model {
                    geometry: ProceduralMesh { primitiveMode: ProceduralMesh.Lines; positions: [Qt.vector3d(dn.pos.x, 0, dn.pos.z), dn.pos] }
                    materials: PrincipledMaterial { baseColor: dn.col; lighting: PrincipledMaterial.NoLighting; opacity: 0.7; alphaMode: PrincipledMaterial.Blend }
                }
                Model {
                    source: "#Cylinder"; position: Qt.vector3d(dn.pos.x, 0.03, dn.pos.z); scale: Qt.vector3d(0.03, 0.0005, 0.03)
                    materials: PrincipledMaterial { baseColor: dn.col; lighting: PrincipledMaterial.NoLighting; opacity: 0.45; alphaMode: PrincipledMaterial.Blend }
                }
                // prediction over T_LOOK (guard)
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
                    materials: PrincipledMaterial { baseColor: dn.col; lighting: PrincipledMaterial.NoLighting; opacity: 0.7; alphaMode: PrincipledMaterial.Blend }
                }
                // flown track: mission (vehicle colour) and ACACT-flown (red)
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
        // predicted closest approach of pairs in conflict (guard)
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
                // risk zone: a translucent disc at the predicted closest approach
                Model {
                    source: "#Cylinder"
                    position: Qt.vector3d((pn.ca.x + pn.cb.x) / 2, (pn.ca.y + pn.cb.y) / 2, (pn.ca.z + pn.cb.z) / 2)
                    scale: Qt.vector3d(root.dSafe / 100, 0.002, root.dSafe / 100)
                    materials: PrincipledMaterial { baseColor: MLTheme.riskColor(pn.p.level); opacity: 0.22; alphaMode: PrincipledMaterial.Blend; lighting: PrincipledMaterial.NoLighting; cullMode: Material.NoCulling }
                }
                Model { source: "#Sphere"; position: pn.ca; scale: Qt.vector3d(0.012, 0.012, 0.012); materials: PrincipledMaterial { baseColor: MLTheme.riskColor(pn.p.level); lighting: PrincipledMaterial.NoLighting } }
                Model { source: "#Sphere"; position: pn.cb; scale: Qt.vector3d(0.012, 0.012, 0.012); materials: PrincipledMaterial { baseColor: MLTheme.riskColor(pn.p.level); lighting: PrincipledMaterial.NoLighting } }
            }
        }
    }
    OrbitCameraController {
        id: orbit
        anchors.fill: view
        origin: originNode
        camera: cam
    }

    // ---- camera presets ----------------------------------------------------------------------
    function viewPreset(k) {
        root.autoOrbit = false
        originNode.eulerRotation = Qt.vector3d(0, 0, 0)
        if (k === "top") { cam.position = Qt.vector3d(0, 140, 0.01); cam.eulerRotation = Qt.vector3d(-89.9, 0, 0) }
        else if (k === "side") { cam.position = Qt.vector3d(0, 12, 110); cam.eulerRotation = Qt.vector3d(-4, 0, 0) }
        else { cam.position = Qt.vector3d(0, 45, 85); cam.eulerRotation = Qt.vector3d(-28, 0, 0) }
    }
    function zoom(f) { cam.position = Qt.vector3d(cam.position.x * f, cam.position.y * f, cam.position.z * f) }

    // labels (2D over the 3D view)
    Repeater {
        model: root._drones.length
        Rectangle {
            readonly property var d: index < root._drones.length ? root._drones[index] : ({})
            readonly property bool ok: root.okOf(d)
            readonly property var sp: { root.tracksRev; root._vTick; root.replayCursor; cam.position; cam.eulerRotation; originNode.eulerRotation; originNode.position; if (!ok) return Qt.vector3d(-1, -1, -1); var p = root.posOf(d); return view.mapFrom3DScene(Qt.vector3d(p.x, p.y + 3, p.z)) }
            readonly property string ph: root.phaseText(d)
            visible: ok && sp.z > 0
            x: sp.x + 10 * root.u; y: sp.y - height - 4 * root.u
            width: lt.implicitWidth + 14 * root.u; height: lt.implicitHeight + 8 * root.u
            radius: 4 * root.u
            color: MLTheme.glass
            border.color: d.own ? MLTheme.warning : root.colorOf(d.id)
            Text {
                id: lt; anchors.centerIn: parent
                text: d.id + "  " + Number(d.alt).toFixed(1) + " m" + (parent.ph !== "" ? "  " + parent.ph : "")
                color: d.own ? MLTheme.warning : root.colorOf(d.id)
                font.family: MLTheme.mono; font.pixelSize: root.presentation ? MLTheme.fsBody : MLTheme.fsLabel; font.weight: Font.Medium
            }
        }
    }

    // header
    Rectangle {
        visible: !root.presentation
        width: parent.width; height: 40 * u
        color: MLTheme.alpha(MLTheme.panelSolid, 0.88)
        Row {
            x: 12 * u; anchors.verticalCenter: parent.verticalCenter; spacing: 10 * u
            MLText { text: root.replay ? qsTr("3D 리플레이") : qsTr("ACACT 3D 상황도"); font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
            MLText { text: root.replay ? qsTr("격자 10 m · 빨간 화살표 = 전방 F (시연 좌표계)") : qsTr("격자 10 m · 굵은 선 50 m · 빨간 화살표 북쪽"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 6 * u; anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * u
            MLIconButton { label: qsTr("기본"); size: 30 * u; tip: qsTr("기본 시점"); onClicked: root.viewPreset("persp") }
            MLIconButton { label: qsTr("위"); size: 30 * u; tip: qsTr("위에서 본 시점"); onClicked: root.viewPreset("top") }
            MLIconButton { label: qsTr("옆"); size: 30 * u; tip: qsTr("옆에서 본 시점 — 고도 차이 확인"); onClicked: root.viewPreset("side") }
            MLIconButton { glyph: "+"; tip: qsTr("확대"); onClicked: root.zoom(0.8) }
            MLIconButton { glyph: "−"; tip: qsTr("축소"); onClicked: root.zoom(1.25) }
            MLIconButton { glyph: "⟲"; tip: qsTr("자동 회전"); checked: root.autoOrbit; onClicked: root.autoOrbit = !root.autoOrbit }
            MLIconButton { glyph: "⌫"; tip: qsTr("궤적 지우기"); visible: !root.replay; onClicked: { root.tracks = ({}); root.tracksRev++ } }
            MLIconButton { glyph: "⛶"; tip: qsTr("전체 화면"); onClicked: root.fullscreenRequested() }
            MLIconButton { visible: root.detachable; glyph: "⧉"; tip: qsTr("새 창으로 분리"); onClicked: root.detachRequested() }
            MLIconButton { visible: root.closable; glyph: "✕"; tip: qsTr("닫기"); onClicked: root.closeRequested() }
        }
    }

    // legend: what each mark means and where the data comes from
    Rectangle {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10 * u
        width: lg.implicitWidth + 20 * u; height: lg.implicitHeight + 14 * u
        radius: 6 * u
        color: MLTheme.alpha(MLTheme.panelSolid, 0.82)
        border.color: MLTheme.line
        Column {
            id: lg
            x: 10 * u; y: 7 * u
            spacing: 3 * u
            Key { c: MLTheme.accent; t: qsTr("비행 궤적 (기체 색)") }
            Key { c: MLTheme.warning; t: qsTr("ACACT 회피 구간") }
            Key { visible: !root.replay; c: MLTheme.accent; dash: true; t: qsTr("계획 경로 (미션 검사)") }
            Key { visible: root._guard; c: MLTheme.caution; t: qsTr("최근접 예측 지점 · 위험 영역") }
            MLText { text: qsTr("반투명 구 = ½ D_SAFE (%1 m) · 기체 모형 ×%2 확대").arg((root.dSafe / 2).toFixed(1)).arg(root.modelScale); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
            MLText {
                text: root.replay ? qsTr("기록 재생 · 자세 기록 없음 → 기수는 이동 방향") : (root._guard ? qsTr("실시간 · ACACT 가드 값 + 기체 자세(텔레메트리)") : qsTr("실시간 · 기체 위치·자세(텔레메트리) · 가드 정지 — 예측 없음"))
                color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
            }
        }
    }

    MLText {
        visible: root._drones.length === 0
        anchors.centerIn: parent
        text: root.replay ? qsTr("재생할 기록을 고르세요") : qsTr("연결된 기체가 없습니다")
        color: MLTheme.dim
        font.pixelSize: MLTheme.fsBody
    }
}
