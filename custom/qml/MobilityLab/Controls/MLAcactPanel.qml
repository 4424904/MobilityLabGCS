import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// ACACT 상황판 (right panel, ACACT tab): what the guard sees and why it acts.
// Every number comes from the guard's own evaluation (MLAcactRuntime → mlGuard.pairs / drones):
// current horizontal separation, vertical separation, predicted minimum separation and the time
// to it (closest point of approach over T_LOOK), the risk level the core assigned, and for each
// vehicle the phase (mission · avoidance · return · operator) and the reason recorded at takeover.
Item {
    id: root
    readonly property real u:       MLTheme.u
    readonly property bool _has:    typeof mlGuard !== "undefined"
    readonly property bool _run:    _has && mlGuard.active
    readonly property var  _cfg:    _has ? mlGuard.config : ({})
    readonly property real dSafe:   _cfg.d_safe !== undefined ? _cfg.d_safe : 10
    readonly property real dEmerg:  _cfg.d_emerg !== undefined ? _cfg.d_emerg : 5.5
    readonly property real vSep:    _cfg.v_sep !== undefined ? _cfg.v_sep : 4
    readonly property real tLook:   _cfg.t_look !== undefined ? _cfg.t_look : 6

    function colorOf(id) { var m = /^D(\d+)$/.exec(id); return MLTheme.vehicleColor(m ? Number(m[1]) : 1) }
    function droneById(id) {
        var ds = mlGuard.drones
        for (var i = 0; i < ds.length; i++) if (ds[i].id === id) return ds[i]
        return null
    }

    Flickable {
        anchors.fill:   parent
        contentHeight:  col.implicitHeight + 24 * u
        clip:           true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id:         col
            x:          12 * u
            y:          12 * u
            width:      root.width - 24 * u
            spacing:    12 * u

            // ---- state ------------------------------------------------------------------
            Rectangle {
                id:     stateCard
                width:  parent.width
                height: stCol.implicitHeight + 24 * u
                radius: 8 * u
                readonly property int  lvl: root._run ? mlGuard.worstLevel : -1
                readonly property bool avoiding: root._run && mlGuard.avoiding > 0
                color:  avoiding ? MLTheme.warningFill : MLTheme.tile
                border.color: avoiding ? MLTheme.warning : (lvl >= 1 ? MLTheme.alpha(MLTheme.caution, 0.6) : MLTheme.line)
                Behavior on color { ColorAnimation { duration: MLTheme.anim } }
                Column {
                    id: stCol
                    x: 14 * u; y: 12 * u; width: parent.width - 28 * u
                    spacing: 8 * u
                    Row {
                        spacing: 10 * u
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10 * u; height: width; radius: width / 2
                            color: !root._run ? MLTheme.faint : (stateCard.avoiding ? MLTheme.warning : MLTheme.riskColor(mlGuard.worstLevel))
                        }
                        MLText {
                            text: {
                                if (!root._has) return qsTr("ACACT 사용 불가")
                                if (!root._run) return qsTr("ACACT 정지")
                                if (mlGuard.avoiding > 0) return qsTr("회피 기동 중 · %1기").arg(mlGuard.avoiding)
                                if (!mlGuard.guardEnabled) return qsTr("일시정지 (HOLD)")
                                return qsTr("감시 중")
                            }
                            font.pixelSize: MLTheme.fsTitle
                            font.weight: Font.DemiBold
                            color: root._run && mlGuard.avoiding > 0 ? MLTheme.warning : MLTheme.bright
                        }
                    }
                    Row {
                        visible: root._run
                        spacing: 22 * u
                        Column {
                            Text { text: qsTr("현재 최근접"); color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                            Text { text: isNaN(mlGuard.closest) ? "—" : Number(mlGuard.closest).toFixed(1) + " m"; color: MLTheme.riskColor(mlGuard.worstLevel); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBig; font.weight: Font.Medium }
                        }
                        Column {
                            Text { text: qsTr("위험도"); color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                            MLChip { text: MLTheme.riskName(mlGuard.worstLevel); tone: MLTheme.riskColor(mlGuard.worstLevel); filled: mlGuard.worstLevel >= 2; height: 26 * u }
                        }
                        Column {
                            Text { text: qsTr("가드 시간"); color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                            Text { text: MLTheme.duration(mlGuard.guardTime); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue }
                        }
                    }
                    MLText {
                        visible: !root._run
                        width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                        color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall
                        text: qsTr("ACACT는 GCS 안에서 실행됩니다. 기체가 연결되면 [ACACT 콘솔]에서 미션 검사와 사전 점검 후 가드를 시작하세요.")
                    }
                    Flow {
                        width: parent.width
                        spacing: 6 * u
                        MLIconButton { label: qsTr("ACACT 콘솔"); glyph: "▣"; checked: MLState.guardConsoleOpen; onClicked: MLState.guardConsoleOpen = !MLState.guardConsoleOpen }
                        MLIconButton { label: qsTr("타임라인"); glyph: "≡"; checked: MLState.acactTimelineOpen; onClicked: MLState.acactTimelineOpen = !MLState.acactTimelineOpen }
                        MLIconButton { label: qsTr("3D 상황도"); glyph: "◭"; checked: MLState.acact3dOpen; onClicked: MLState.acact3dOpen = !MLState.acact3dOpen }
                    }
                }
            }

            // ---- pairs --------------------------------------------------------------------
            MLSectionTitle { text: qsTr("기체 쌍 충돌 위험"); detail: root._run ? qsTr("예측 %1초").arg(root.tLook.toFixed(0)) : "" }
            MLText {
                visible: !root._run || mlGuard.pairs.length === 0
                width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall
                text: root._run ? qsTr("두 기체 이상이 비행 중이면 쌍마다 현재 이격, 예측 최소 이격과 최근접 시점이 표시됩니다.") : qsTr("가드 정지 중 — 표시할 계산값 없음")
            }
            Repeater {
                model: root._run ? mlGuard.pairs.length : 0
                Rectangle {
                    id: pr
                    readonly property var p: index < mlGuard.pairs.length ? mlGuard.pairs[index] : ({ a: "", b: "", d: 0, dz: 0, cpa: 0, tcpa: 0, level: 0 })
                    readonly property bool sameLayer: p.dz <= root.vSep
                    width: col.width
                    height: prCol.implicitHeight + 20 * u
                    radius: 8 * u
                    color: p.level >= 2 ? MLTheme.warningFill : (p.level === 1 ? MLTheme.cautionFill : MLTheme.tile)
                    border.color: MLTheme.alpha(MLTheme.riskColor(p.level), p.level > 0 ? 0.7 : 0.25)
                    Column {
                        id: prCol
                        x: 12 * u; y: 10 * u; width: parent.width - 24 * u
                        spacing: 8 * u
                        Item {
                            width: parent.width; height: 22 * u
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6 * u
                                Text { text: pr.p.a; color: root.colorOf(pr.p.a); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                                Text { text: "↔"; color: MLTheme.dim; font.pixelSize: MLTheme.fsBody }
                                Text { text: pr.p.b; color: root.colorOf(pr.p.b); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                            }
                            MLChip { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: MLTheme.riskName(pr.p.level); tone: MLTheme.riskColor(pr.p.level); filled: pr.p.level >= 2; blink: pr.p.level >= 2 }
                        }
                        // separation scale: 0 … 3 × D_SAFE, emergency and safe limits, now (●) and predicted minimum (○)
                        MLSeparationBar {
                            width: parent.width
                            now: pr.p.d; predicted: pr.p.cpa
                            dSafe: root.dSafe; dEmerg: root.dEmerg
                            level: pr.p.level
                            dimmed: !pr.sameLayer
                        }
                        Grid {
                            width: parent.width
                            columns: 4
                            rowSpacing: 2 * u
                            readonly property real cw: width / 4
                            Repeater {
                                model: [
                                    { k: qsTr("현재 수평"), v: pr.p.d.toFixed(1), u: "m" },
                                    { k: qsTr("고도차"), v: pr.p.dz.toFixed(1), u: "m" },
                                    { k: qsTr("예측 최소"), v: pr.p.cpa.toFixed(1), u: "m" },
                                    { k: qsTr("최근접까지"), v: pr.p.tcpa < 0.05 ? qsTr("멀어짐") : (pr.p.tcpa >= root.tLook ? "> " + root.tLook.toFixed(0) : pr.p.tcpa.toFixed(1)), u: pr.p.tcpa < 0.05 ? "" : "s" }
                                ]
                                Column {
                                    width: parent.cw
                                    Text { text: modelData.k; color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                                    Text { text: modelData.v + " " + modelData.u; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue }
                                }
                            }
                        }
                        MLText {
                            width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                            font.pixelSize: MLTheme.fsLabel
                            color: MLTheme.label
                            text: {
                                var p = pr.p
                                var s = !pr.sameLayer ? qsTr("수직 분리 %1 m 초과 — 다른 고도층, 수평 이격 무관").arg(root.vSep.toFixed(0))
                                      : (p.level >= 2 ? qsTr("비상 이격 %1 m 이내 — 즉시 회피").arg(root.dEmerg.toFixed(1))
                                      : (p.level === 1 ? qsTr("%1초 안에 안전 이격 %2 m 미만 예측 — 회피 개입 대상").arg(root.tLook.toFixed(0)).arg(root.dSafe.toFixed(0))
                                      : qsTr("예측 경로상 안전 이격 유지")))
                                if (p.min !== undefined && p.min !== null) s += qsTr(" · 비행 중 최소 %1 m").arg(Number(p.min).toFixed(1))
                                return s
                            }
                        }
                    }
                }
            }

            // ---- vehicles -----------------------------------------------------------------
            MLSectionTitle { text: qsTr("기체별 ACACT 상태"); visible: root._run }
            Repeater {
                model: root._run ? mlGuard.drones.length : 0
                Rectangle {
                    readonly property var d: index < mlGuard.drones.length ? mlGuard.drones[index] : ({ id: "", phase: "", takeovers: 0, ownedTime: 0 })
                    width: col.width
                    height: dCol.implicitHeight + 16 * u
                    radius: 8 * u
                    color: MLTheme.tile
                    border.color: d.phase === "avoid" ? MLTheme.warning : MLTheme.line
                    Rectangle { x: 0; y: 6 * u; width: 4 * u; height: parent.height - 12 * u; radius: 2 * u; color: root.colorOf(d.id) }
                    Column {
                        id: dCol
                        x: 14 * u; y: 8 * u; width: parent.width - 24 * u
                        spacing: 4 * u
                        Item {
                            width: parent.width; height: 22 * u
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8 * u
                                Text { text: d.id; color: root.colorOf(d.id); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                                Text { text: d.mode; color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                            }
                            MLChip {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                readonly property var names: ({ avoid: qsTr("회피 기동"), "return": qsTr("미션 복귀"), operator: qsTr("운용자 제어"), yield: qsTr("양보"), lost: qsTr("두절"), mission: qsTr("미션 · 감시"), ground: qsTr("지상"), other: qsTr("감시 외 모드") })
                                text: names[d.phase] || d.phase
                                tone: d.phase === "avoid" || d.phase === "lost" ? MLTheme.warning : (d.phase === "mission" ? MLTheme.active : (d.phase === "ground" || d.phase === "other" ? MLTheme.dim : MLTheme.caution))
                                blink: d.phase === "avoid"
                            }
                        }
                        Text {
                            text: qsTr("개입 %1회 · Offboard %2 · 제어권 %3").arg(d.takeovers).arg(MLTheme.duration(d.ownedTime))
                                  .arg(d.own ? qsTr("ACACT") : (d.lock ? qsTr("운용자 (가드 해제)") : qsTr("FC 미션")))
                            color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel
                        }
                        MLText {
                            visible: (d.reason || d.lastReason || "") !== ""
                            width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                            text: (d.reason ? qsTr("개입 사유: ") : qsTr("마지막 개입: ")) + (d.reason || d.lastReason)
                            color: d.reason ? MLTheme.text : MLTheme.dim
                            font.pixelSize: MLTheme.fsLabel
                        }
                    }
                }
            }

            // ---- limits -------------------------------------------------------------------
            MLSectionTitle { text: qsTr("판단 기준") }
            Grid {
                width: parent.width
                columns: 2
                rowSpacing: 4 * u
                Repeater {
                    model: [
                        { k: qsTr("안전 이격 D_SAFE"), v: root.dSafe.toFixed(1) + " m" },
                        { k: qsTr("비상 이격 D_EMERG"), v: root.dEmerg.toFixed(1) + " m" },
                        { k: qsTr("수직 분리 V_SEP"), v: root.vSep.toFixed(1) + " m" },
                        { k: qsTr("예측 구간 T_LOOK"), v: root.tLook.toFixed(1) + " s" }
                    ]
                    Row {
                        width: col.width / 2
                        spacing: 6 * u
                        Text { text: modelData.k; color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                        Text { text: modelData.v; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                    }
                }
            }
        }
    }
}
