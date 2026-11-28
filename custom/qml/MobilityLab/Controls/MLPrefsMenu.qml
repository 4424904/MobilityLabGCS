import QtQuick
import QtQuick.Controls

import QGroundControl

// 환경 설정 (⚙ in the top bar): operating mode, display, language, help, shortcuts, graphics.
// Everything here is saved for this Windows / Linux user and restored at the next start.
Rectangle {
    id: root
    signal closeRequested()
    property var shortcuts: null            // MLShortcuts of the fly view
    readonly property real u: MLTheme.u
    readonly property var  _scale: QGroundControl.settingsManager.appSettings.uiScalePercent
    property string _capture: ""            // action id waiting for a key press

    radius: 14 * u
    color:  MLTheme.panelSolid
    border.color: MLTheme.lineStrong

    component Seg: Flow {
        id: seg
        width: parent ? parent.width : 300
        property var options: []      // [{k, t}]
        property string value
        signal picked(string k)
        spacing: 4 * MLTheme.u
        Repeater {
            model: seg.options
            Rectangle {
                readonly property bool on: seg.value === modelData.k
                width: segT.implicitWidth + 26 * MLTheme.u; height: 36 * MLTheme.u; radius: 6 * MLTheme.u
                color: on ? MLTheme.alpha(MLTheme.accent, 0.16) : (sMa.containsMouse ? MLTheme.hover : MLTheme.tile)
                border.color: on ? MLTheme.accent : MLTheme.line
                MLText { id: segT; anchors.centerIn: parent; text: modelData.t; color: parent.on ? MLTheme.accent : MLTheme.text; font.pixelSize: MLTheme.fsSmall; font.weight: parent.on ? Font.DemiBold : Font.Normal }
                MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(modelData.k) }
            }
        }
    }
    component RowItem: Item {
        property string title
        property string hint
        default property alias content: holder.data
        width: parent ? parent.width : 0; height: Math.max(48 * MLTheme.u, holder.childrenRect.height + 8 * MLTheme.u, tCol.implicitHeight + 8 * MLTheme.u)
        Column {
            id: tCol
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.36
            MLText { text: title; font.pixelSize: MLTheme.fsBody }
            MLText { visible: hint !== ""; text: hint; width: parent.width; wrapMode: Text.WordWrap; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
        }
        Item { id: holder; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.62; height: childrenRect.height }
    }

    Item {
        id: head
        width: parent.width; height: 64 * u
        MLText { x: 24 * u; anchors.verticalCenter: parent.verticalCenter; text: qsTr("환경 설정"); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold }
        MLText { anchors.right: closeB.left; anchors.rightMargin: 12 * u; anchors.verticalCenter: parent.verticalCenter; text: qsTr("이 PC 사용자 계정에 자동 저장됩니다"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
        MLIconButton { id: closeB; anchors.right: parent.right; anchors.rightMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter; glyph: "✕"; tip: qsTr("닫기 (Esc)"); onClicked: root.closeRequested() }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
    }

    Flickable {
        anchors.top: head.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        anchors.margins: 4 * u
        contentHeight: col.implicitHeight + 30 * u
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: col
            x: 22 * u; y: 14 * u; width: root.width - 52 * u
            spacing: 8 * u

            MLSectionTitle { text: qsTr("운용 모드") }
            RowItem {
                title: qsTr("화면 모드"); hint: qsTr("바꿔도 비행·연결·미션·ACACT 상태는 그대로입니다")
                Seg { value: MLState.uiMode; options: [{ k: "standard", t: "STANDARD" }, { k: "advanced", t: "ADVANCED" }, { k: "showcase", t: "SHOWCASE" }]; onPicked: (k) => MLState.setUiMode(k) }
            }

            MLSectionTitle { text: qsTr("화면") }
            RowItem {
                title: qsTr("테마"); hint: qsTr("고대비: 야외 직사광선용 — 검은 글씨, 진한 선, 불투명 패널")
                Seg {
                    value: MLTheme.contrast ? "hc" : (MLTheme.day ? "day" : "night")
                    options: [{ k: "night", t: qsTr("야간") }, { k: "day", t: qsTr("주간") }, { k: "hc", t: qsTr("고대비") }]
                    onPicked: (k) => { if (k === "hc") { MLTheme.setDay(true); MLTheme.setContrast(true) } else { MLTheme.setContrast(false); MLTheme.setDay(k === "day") } }
                }
            }
            RowItem {
                title: qsTr("UI 배율 · 글자 크기"); hint: qsTr("FHD 노트북은 100–110%, QHD 120%, 4K 150%를 권장")
                Seg {
                    value: root._scale ? String(root._scale.rawValue) : "100"
                    options: [{ k: "90", t: "90%" }, { k: "100", t: "100%" }, { k: "110", t: "110%" }, { k: "120", t: "120%" }, { k: "135", t: "135%" }, { k: "150", t: "150%" }]
                    onPicked: (k) => { if (root._scale) root._scale.rawValue = Number(k) }
                }
            }
            RowItem {
                title: qsTr("언어")
                Seg {
                    value: typeof mlUi !== "undefined" ? mlUi.language : "ko"
                    options: [{ k: "ko", t: "한국어" }, { k: "en", t: "English" }]
                    onPicked: (k) => { if (typeof mlUi !== "undefined") mlUi.language = k }
                }
            }
            RowItem {
                title: qsTr("성능 모드"); hint: qsTr("지도·3D·애니메이션 부하만 바뀝니다. 비행 통신, ACACT 계산, 안전 기능은 어떤 모드에서도 같습니다")
                Seg {
                    value: MLState.gfxQuality === "low" ? "lite" : MLState.gfxQuality
                    options: [{ k: "auto", t: qsTr("자동") }, { k: "lite", t: qsTr("경량") }, { k: "balanced", t: qsTr("균형") }, { k: "high", t: qsTr("고품질") }]
                    onPicked: (k) => MLState.gfxQuality = k
                }
            }

            MLSectionTitle { text: qsTr("음성 · 경고음") }
            RowItem {
                title: qsTr("음성 경고"); hint: qsTr("경고 제목을 읽어 줍니다 — 같은 경고는 30초에 한 번")
                Seg {
                    value: !MLState.voiceAlerts ? "off" : String(MLState.voiceMinLevel)
                    options: [{ k: "off", t: qsTr("끔") }, { k: "4", t: qsTr("긴급만") }, { k: "3", t: qsTr("위험 이상") }, { k: "2", t: qsTr("주의 이상") }]
                    onPicked: (k) => { if (k === "off") MLState.voiceAlerts = false; else { MLState.voiceAlerts = true; MLState.voiceMinLevel = Number(k) } }
                }
            }
            RowItem {
                title: qsTr("음량"); hint: qsTr("QGC 음성 출력 설정과 같은 값")
                Row {
                    spacing: 10 * MLTheme.u
                    readonly property var vol: QGroundControl.settingsManager.appSettings.audioVolume
                    readonly property var mute: QGroundControl.settingsManager.appSettings.audioMuted
                    Slider {
                        width: 220 * MLTheme.u
                        from: 0; to: 100; stepSize: 5
                        value: parent.vol ? Number(parent.vol.rawValue) : 100
                        onMoved: if (parent.vol) parent.vol.rawValue = value
                    }
                    MLText { anchors.verticalCenter: parent.verticalCenter; text: parent.vol ? Number(parent.vol.rawValue).toFixed(0) + "%" : ""; font.pixelSize: MLTheme.fsSmall }
                    MLIconButton { anchors.verticalCenter: parent.verticalCenter; size: 30 * MLTheme.u; label: parent.mute && parent.mute.rawValue ? qsTr("음소거됨") : qsTr("음소거"); checked: parent.mute && parent.mute.rawValue; onClicked: if (parent.mute) parent.mute.rawValue = !parent.mute.rawValue }
                    MLIconButton { anchors.verticalCenter: parent.verticalCenter; size: 30 * MLTheme.u; label: qsTr("시험"); onClicked: if (typeof mlUi !== "undefined") mlUi.say(qsTr("음성 경고 시험")) }
                }
            }

            MLSectionTitle { text: qsTr("도움말") }
            RowItem {
                title: qsTr("버튼 설명 (툴팁)")
                Seg { value: MLState.helpTips ? "on" : "off"; options: [{ k: "on", t: qsTr("표시") }, { k: "off", t: qsTr("숨김") }]; onPicked: (k) => MLState.helpTips = (k === "on") }
            }
            RowItem {
                title: qsTr("시작 안내")
                MLCommandButton { compact: true; twoStep: false; text: qsTr("다시 열기"); onClicked: { MLState.onboardingDone = false; MLState.onboardingOpen = true; root.closeRequested() } }
            }

            MLSectionTitle { text: qsTr("단축키"); detail: qsTr("비행 명령(시동·이륙·HOLD·복귀·착륙·비상정지)에는 단축키를 두지 않습니다") }
            Repeater {
                model: root.shortcuts ? root.shortcuts.actions : []
                Rectangle {
                    width: col.width; height: 40 * u; radius: 6 * u
                    readonly property string seq: { MLState.shortcutsJson; return root.shortcuts.seqFor(modelData.id) }
                    readonly property bool capturing: root._capture === modelData.id
                    color: capturing ? MLTheme.alpha(MLTheme.accent, 0.12) : (index % 2 ? "transparent" : MLTheme.tile)
                    MLText { x: 12 * u; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: MLTheme.fsSmall }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 8 * u; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8 * u
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(90 * u, kT.implicitWidth + 20 * u); height: 28 * u; radius: 5 * u
                            color: MLTheme.panelRaised; border.color: parent.parent.capturing ? MLTheme.accent : MLTheme.line
                            Text { id: kT; anchors.centerIn: parent; text: parent.parent.parent.capturing ? qsTr("키를 누르세요…") : (parent.parent.parent.seq || "—"); color: MLTheme.text; font.family: parent.parent.parent.capturing ? MLTheme.sans : MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                        }
                        MLIconButton { anchors.verticalCenter: parent.verticalCenter; size: 28 * u; label: qsTr("변경"); onClicked: { root._capture = modelData.id; keyCatcher.forceActiveFocus() } }
                    }
                }
            }
            Row {
                spacing: 10 * u
                MLCommandButton { compact: true; twoStep: false; text: qsTr("기본값으로"); onClicked: if (root.shortcuts) root.shortcuts.resetAll() }
                MLText { id: conflict; anchors.verticalCenter: parent.verticalCenter; color: MLTheme.caution; font.pixelSize: MLTheme.fsLabel }
            }
        }
    }

    // key capture for rebinding
    Item {
        id: keyCatcher
        focus: root._capture !== ""
        Keys.onPressed: (e) => {
            if (root._capture === "") return
            e.accepted = true
            if (e.key === Qt.Key_Escape) { root._capture = ""; return }
            if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta].indexOf(e.key) >= 0) return
            var parts = []
            if (e.modifiers & Qt.ControlModifier) parts.push("Ctrl")
            if (e.modifiers & Qt.AltModifier) parts.push("Alt")
            if (e.modifiers & Qt.ShiftModifier) parts.push("Shift")
            var name = e.key >= Qt.Key_F1 && e.key <= Qt.Key_F35 ? "F" + (e.key - Qt.Key_F1 + 1) : (e.text && e.text.trim() !== "" ? e.text.toUpperCase() : "")
            if (name === "") return
            parts.push(name)
            var seq = parts.join("+")
            var o = root.shortcuts.owner(seq, root._capture)
            conflict.text = o ? qsTr("%1 — '%2'에서 이 키를 빼고 여기에 지정했습니다").arg(seq).arg(o.name) : ""
            if (o) root.shortcuts.bind(o.id, "")
            root.shortcuts.bind(root._capture, seq)
            root._capture = ""
        }
    }
}
