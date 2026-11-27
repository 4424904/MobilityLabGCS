import QtQuick
import QtQuick.Controls

import QGroundControl

// SHOWCASE — 기술 시연 화면 (full window).
//
// Presents ACACT multi-vehicle collision avoidance for briefings, investors and exhibitions.
// Two sources only, both real computations:
//   demo    the built-in demo (simulated aircraft, real ACACT guard). Real links are blocked by the
//           demo itself; every screen carries the DEMO mark and nothing is recorded as a test.
//   replay  a recorded guard log (mlAnalysis): positions, separations and events as logged.
// There are no flight controls on this screen. It can only be entered with no real vehicle
// connected (MLState.setUiMode), and the fly view leaves it if a real vehicle appears.
Rectangle {
    id: root
    signal exitRequested()
    signal fullscreenRequested()
    readonly property real u:       MLTheme.u
    readonly property bool _demoOk: typeof mlDemo !== "undefined"
    readonly property bool _demo:   _demoOk && mlDemo.active
    readonly property bool _an:     typeof mlAnalysis !== "undefined"
    readonly property bool _g:      typeof mlGuard !== "undefined"
    readonly property string source: _demo ? "demo" : (MLState.showcaseSource === "replay" && _an && mlAnalysis.loaded ? "replay" : "")
    readonly property bool _replayIsDemo: source === "replay" && mlAnalysis.info && mlAnalysis.info.opMode === "demo"

    // ---- replay transport ---------------------------------------------------------------------
    property real cursor: 0
    property bool playing: false
    property real speed: 2
    readonly property real duration: _an && mlAnalysis.loaded ? mlAnalysis.duration : 0
    readonly property var replayState: source === "replay" ? mlAnalysis.stateAt(cursor) : []
    Timer {
        interval: 100; repeat: true; running: root.playing && root.source === "replay" && root.visible
        onTriggered: { root.cursor = Math.min(root.duration, root.cursor + 0.1 * root.speed); if (root.cursor >= root.duration) root.playing = false }
    }
    function startReplay(stamp) {
        if (!_an || !mlAnalysis.load(stamp)) return
        MLState.showcaseSource = "replay"
        cursor = 0; playing = true
    }
    function startDemo(sc) {
        if (!_demoOk) return
        if (mlDemo.startBlockReason() !== "") { blockNote.text = mlDemo.startBlockReason(); return }
        if (typeof mlGuard !== "undefined" && mlGuard.opMode === "field") mlGuard.setOpMode("sim")
        if (mlDemo.start(sc)) { MLState.showcaseSource = "demo"; autoTimer.restart() }
    }
    Timer { id: autoTimer; interval: 1500; onTriggered: MLState.demoAutoRequested = true }

    // separation of each pair: live from the guard, replay from the log series at the cursor
    readonly property var pairRows: {
        var out = []
        if (source === "demo" && _g && mlGuard.active) {
            var ps = mlGuard.pairs
            for (var i = 0; i < ps.length; i++) out.push({ a: ps[i].a, b: ps[i].b, d: ps[i].d, dz: ps[i].dz, cpa: ps[i].cpa, tcpa: ps[i].tcpa, level: ps[i].level, min: ps[i].min })
        } else if (source === "replay") {
            var pr = mlAnalysis.pairs
            for (var k = 0; k < pr.length; k++) {
                var s = pr[k].series, cur = null, mn = NaN
                for (var j = 0; j < s.length && s[j][0] <= cursor; j++) { cur = s[j]; if (isNaN(mn) || s[j][1] < mn) mn = s[j][1] }
                out.push({ a: pr[k].a, b: pr[k].b, d: cur ? cur[1] : NaN, dz: cur ? cur[2] : NaN, cpa: NaN, tcpa: NaN, level: -1, min: mn })
            }
        }
        return out
    }
    onPairRowsChanged: if (typeof mlTour !== "undefined" && mlTour) console.log("MLTOUR showcase pairs " + pairRows.length + " source " + source)
    readonly property var eventRows: {
        var out = []
        if (source === "demo") {
            for (var i = 0; i < MLState.events.count && out.length < 7; i++) { var e = MLState.events.get(i); if (e.src === "ACACT") out.push({ t: e.t, text: e.text.replace(/^ACACT · /, ""), level: e.level }) }
        } else if (source === "replay") {
            var ev = mlAnalysis.events
            for (var k = ev.length - 1; k >= 0 && out.length < 7; k--) if (ev[k].t <= cursor) out.push({ t: MLTheme.duration(ev[k].t), text: ev[k].who + " · " + ev[k].text, level: /회피|개입/.test(ev[k].text) ? 2 : 0 })
        }
        return out
    }
    readonly property var st: MLAcactStatus.evaluate(_g ? mlGuard : null)

    color: MLTheme.bg

    // ---- header -------------------------------------------------------------------------------
    Rectangle {
        id: head
        width: parent.width; height: 68 * u
        color: MLTheme.panelSolid
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2 * u; color: MLTheme.brand }
        Row {
            x: 24 * u; anchors.verticalCenter: parent.verticalCenter
            spacing: 16 * u
            Image { anchors.verticalCenter: parent.verticalCenter; source: "/MobilityLab/logo.svg"; sourceSize.height: 28 * u; fillMode: Image.PreserveAspectFit }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                MLText { text: "MOBILITY LAB"; font.pixelSize: 15 * u; font.weight: Font.DemiBold; font.letterSpacing: 2.6 * u }
                MLText { text: qsTr("ACACT 다중기체 실시간 충돌 회피"); color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.source !== ""
                width: srcT.implicitWidth + 24 * u; height: 32 * u; radius: 16 * u
                readonly property bool demoish: root.source === "demo" || root._replayIsDemo
                color: MLTheme.alpha(demoish ? MLTheme.demo : MLTheme.accent, 0.16)
                border.color: demoish ? MLTheme.demo : MLTheme.accent
                MLText {
                    id: srcT; anchors.centerIn: parent
                    text: root.source === "demo" ? qsTr("DEMO · 시뮬레이션 기체 · 실기체 링크 차단 · 시험 기록 아님")
                        : (root._replayIsDemo ? qsTr("비행 기록 재생 · 데모 기록 (시험 기록 아님)") : qsTr("비행 기록 재생 · %1").arg(root._an ? mlAnalysis.stamp : ""))
                    color: parent.demoish ? MLTheme.demo : MLTheme.accent
                    font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 16 * u; anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * u
            MLIconButton { size: 38 * u; visible: root.source !== ""; label: qsTr("다른 시연"); onClicked: { if (root._demo) mlDemo.stop(); MLState.showcaseSource = ""; root.playing = false } }
            MLIconButton { size: 38 * u; glyph: "⛶"; tip: qsTr("전체 화면 (F11)"); onClicked: root.fullscreenRequested() }
            MLIconButton { size: 38 * u; glyph: "✕"; label: qsTr("시연 종료"); tip: qsTr("이전 화면 모드로 (Esc) — 데모가 실행 중이면 계속 실행됩니다"); onClicked: root.exitRequested() }
        }
    }

    // ---- main: 3D scene + side column -------------------------------------------------------------
    Item {
        id: main
        anchors.top: head.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        visible: root.source !== ""

        Loader {
            id: sceneLoader
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: transport.visible ? transport.top : parent.bottom
            anchors.right: side.left
            active: root.visible && root.source !== ""
            sourceComponent: Component {
                MLAcact3D {
                    presentation: true
                    detachable: false
                    closable: false
                    replay: root.source === "replay"
                    replayDrones: root.replayState
                    replayTracks: root.source === "replay" ? mlAnalysis.tracks : []
                    replayCursor: root.cursor
                    dSafeOverride: root.source === "replay" && mlAnalysis.verdict && mlAnalysis.verdict.dSafe ? Number(mlAnalysis.verdict.dSafe) : NaN
                }
            }
        }
        // view buttons over the scene
        Row {
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 16 * u
            spacing: 6 * u
            visible: !!sceneLoader.item
            MLIconButton { size: 36 * u; label: qsTr("기본 시점"); onClicked: sceneLoader.item.viewPreset("persp") }
            MLIconButton { size: 36 * u; label: qsTr("위에서"); onClicked: sceneLoader.item.viewPreset("top") }
            MLIconButton { size: 36 * u; label: qsTr("옆에서 · 고도차"); onClicked: sceneLoader.item.viewPreset("side") }
            MLIconButton { size: 36 * u; glyph: "⟲"; label: qsTr("자동 회전"); checked: !!sceneLoader.item && sceneLoader.item.autoOrbit; onClicked: sceneLoader.item.autoOrbit = !sceneLoader.item.autoOrbit }
        }

        // replay transport
        Rectangle {
            id: transport
            visible: root.source === "replay"
            anchors.left: parent.left; anchors.right: side.left; anchors.bottom: parent.bottom
            height: 64 * u
            color: MLTheme.panelSolid
            Row {
                x: 16 * u; anchors.verticalCenter: parent.verticalCenter
                spacing: 10 * u
                MLIconButton { size: 40 * u; glyph: root.playing ? "" : "▶"; label: root.playing ? qsTr("일시정지") : qsTr("재생"); onClicked: { if (root.cursor >= root.duration) root.cursor = 0; root.playing = !root.playing } }
                Repeater {
                    model: [1, 2, 4, 8]
                    MLIconButton { size: 40 * u; label: modelData + "×"; checked: root.speed === modelData; onClicked: root.speed = modelData }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: MLTheme.duration(root.cursor) + " / " + MLTheme.duration(root.duration); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody }
            }
            Slider {
                anchors.right: parent.right; anchors.rightMargin: 16 * u; anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.42
                from: 0; to: Math.max(1, root.duration); value: root.cursor
                onMoved: root.cursor = value
            }
        }

        // side column: state, pairs, vehicles, events
        Rectangle {
            id: side
            anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: Math.max(420 * u, parent.width * 0.27)
            color: MLTheme.panelSolid
            Rectangle { width: 1; height: parent.height; color: MLTheme.line }
            Flickable {
                anchors.fill: parent
                contentHeight: sCol.implicitHeight + 40 * u
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: sCol
                    x: 22 * u; y: 20 * u; width: side.width - 44 * u
                    spacing: 18 * u

                    // ACACT state (live demo) or replay verdict
                    Rectangle {
                        width: parent.width; height: stC.implicitHeight + 28 * u; radius: 12 * u
                        readonly property color tone: root.source === "demo" ? MLAcactStatus.color(root.st.key) : (mlAnalysis.verdict && mlAnalysis.verdict.pass ? MLTheme.active : MLTheme.warning)
                        color: MLTheme.alpha(tone, 0.10); border.color: MLTheme.alpha(tone, 0.8); border.width: 2
                        Column {
                            id: stC
                            x: 18 * u; y: 14 * u; width: parent.width - 36 * u
                            spacing: 6 * u
                            MLText { text: "ACACT"; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 1.4 * u }
                            MLText {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: root.source === "demo" ? root.st.name : (mlAnalysis.verdict && mlAnalysis.verdict.pass ? qsTr("이격 기준 충족") : qsTr("이격 기준 미충족"))
                                font.pixelSize: 30 * u; font.weight: Font.DemiBold; color: parent.parent.tone
                            }
                            MLText {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: root.source === "demo" ? root.st.action : (mlAnalysis.verdict && mlAnalysis.verdict.minSame !== undefined && mlAnalysis.verdict.minSame !== null ? qsTr("기록 전체: 같은 층 최소 수평 이격 %1 m (긴급 거리 %2 m) — 기록 기반 자동 판정, 시험 책임자 검토 필요").arg(Number(mlAnalysis.verdict.minSame).toFixed(1)).arg(Number(mlAnalysis.verdict.dEmerg).toFixed(1)) : "")
                                color: MLTheme.label; font.pixelSize: MLTheme.fsSmall
                            }
                        }
                    }

                    // pairs
                    MLSectionTitle { text: qsTr("기체 간 이격"); detail: root.source === "demo" ? qsTr("ACACT 계산값") : qsTr("기록값") }
                    Repeater {
                        model: root.pairRows
                        Column {
                            width: sCol.width
                            spacing: 6 * u
                            Row {
                                spacing: 10 * u
                                Text { text: modelData.a + " ↔ " + modelData.b; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue; font.weight: Font.DemiBold }
                                MLChip { visible: modelData.level >= 0; text: MLTheme.riskName(modelData.level); tone: MLTheme.riskColor(modelData.level); blink: modelData.level >= 1 }
                            }
                            Row {
                                spacing: 22 * u
                                Repeater {
                                    model: [
                                        { l: qsTr("현재"), v: modelData.d, unit: "m" },
                                        { l: qsTr("예측 최소"), v: modelData.cpa, unit: "m" },
                                        { l: qsTr("최근접까지"), v: modelData.tcpa, unit: "s" },
                                        { l: root.source === "demo" ? qsTr("기록 최소") : qsTr("지금까지 최소"), v: modelData.min, unit: "m" }
                                    ]
                                    Column {
                                        visible: !isNaN(modelData.v) && modelData.v !== null && modelData.v !== undefined
                                        MLText { text: modelData.l; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                        Row {
                                            spacing: 3 * u
                                            Text { id: pv; text: Number(modelData.v).toFixed(1); color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: 28 * u; font.weight: Font.Medium }
                                            MLText { anchors.baseline: pv.baseline; text: modelData.unit; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
                                        }
                                    }
                                }
                            }
                            MLSeparationBar {
                                width: parent.width
                                now: modelData.d
                                predicted: modelData.cpa
                                level: Math.max(0, modelData.level)
                                dSafe: root._g && mlGuard.config.d_safe ? mlGuard.config.d_safe : 10
                                dEmerg: root._g && mlGuard.config.d_emerg ? mlGuard.config.d_emerg : 5.5
                            }
                        }
                    }
                    MLText { visible: root.pairRows.length === 0; text: root.source === "demo" ? qsTr("ACACT 가드 시작 대기 — 자동 시연이 곧 시작합니다") : qsTr("이 기록에는 기체 쌍이 없습니다"); color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall; width: parent.width; wrapMode: Text.WordWrap }

                    // events
                    MLSectionTitle { text: qsTr("ACACT 이벤트") }
                    Repeater {
                        model: root.eventRows
                        Row {
                            width: sCol.width
                            spacing: 10 * u
                            Text { text: modelData.t; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; width: 62 * u }
                            MLText { width: parent.width - 72 * u; text: modelData.text; wrapMode: Text.WordWrap; color: modelData.level >= 2 ? MLTheme.caution : MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                        }
                    }
                }
            }
        }
    }

    // ---- source picker --------------------------------------------------------------------------
    Item {
        anchors.top: head.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        visible: root.source === ""
        Column {
            anchors.centerIn: parent
            width: Math.min(1200 * u, parent.width - 80 * u)
            spacing: 26 * u
            Column {
                spacing: 6 * u
                MLText { text: qsTr("무엇을 보여 줄까요?"); font.pixelSize: MLTheme.fsHuge; font.weight: Font.DemiBold }
                MLText { text: qsTr("시연 화면은 비행 조작 버튼이 없는 발표 전용 화면입니다. 실기체가 연결되면 자동으로 이전 화면으로 돌아갑니다."); color: MLTheme.label; font.pixelSize: MLTheme.fsBody }
            }
            MLText { id: blockNote; visible: text !== ""; color: MLTheme.caution; font.pixelSize: MLTheme.fsBody }
            MLSectionTitle { text: qsTr("실시간 데모 — GCS 내장 시뮬레이션 기체 + 실제 ACACT 가드"); width: parent.width }
            Row {
                spacing: 16 * u
                Repeater {
                    model: root._demoOk ? mlDemo.scenarios : []
                    Rectangle {
                        width: (1200 * u - 32 * u) / 3; height: 150 * u; radius: 12 * u
                        color: dMa.containsMouse ? MLTheme.alpha(MLTheme.demo, 0.14) : MLTheme.tile
                        border.color: dMa.containsMouse ? MLTheme.demo : MLTheme.line
                        Column {
                            x: 20 * u; y: 18 * u; width: parent.width - 40 * u
                            spacing: 8 * u
                            MLText { text: modelData.title; font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold }
                            MLText { text: modelData.text; color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall; width: parent.width; wrapMode: Text.WordWrap }
                        }
                        MLText { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 16 * u; text: qsTr("▶ 시작"); color: MLTheme.demo; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                        MouseArea { id: dMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.startDemo(modelData.key) }
                    }
                }
            }
            MLSectionTitle { text: qsTr("비행 기록 재생 — ACACT 가드 기록"); width: parent.width }
            Flow {
                width: parent.width
                spacing: 10 * u
                Repeater {
                    model: root._an ? mlAnalysis.sessions.slice(0, 8) : []
                    Rectangle {
                        width: (parent.width - 30 * u) / 4; height: 74 * u; radius: 10 * u
                        color: rMa.containsMouse ? MLTheme.hover : MLTheme.tile
                        border.color: MLTheme.line
                        Column {
                            x: 14 * u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 28 * u
                            Text { text: modelData.stamp; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                            MLText { text: (modelData.opMode === "demo" ? "DEMO · " : (modelData.opMode === "field" ? qsTr("실비행 · ") : (modelData.opMode === "sim" ? "SITL · " : ""))) + (modelData.vehicles || "") + (modelData.plan ? " · " + modelData.plan : ""); color: modelData.opMode === "demo" ? MLTheme.demo : MLTheme.dim; font.pixelSize: MLTheme.fsLabel; width: parent.width; elide: Text.ElideRight }
                        }
                        MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.startReplay(modelData.stamp) }
                    }
                }
                MLText { visible: !root._an || mlAnalysis.sessions.length === 0; text: qsTr("저장된 ACACT 가드 기록이 없습니다"); color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall }
            }
        }
    }
    Component.onCompleted: {
        if (_an) mlAnalysis.refresh()
        if (source === "replay") { cursor = 0; speed = 8; playing = true }   // opened on a loaded record: play it
    }
}
