import QtQuick
import QtQuick.Controls

// Text input in the console's own look (dark/light/high-contrast tokens), instead of the platform style.
TextField {
    id: f
    readonly property real u: MLTheme.u
    font.pixelSize: MLTheme.fsSmall
    font.family: MLTheme.sans
    color: MLTheme.text
    placeholderTextColor: MLTheme.faint
    selectionColor: MLTheme.accent
    selectedTextColor: MLTheme.onAccent
    leftPadding: 10 * u; rightPadding: 10 * u; topPadding: 7 * u; bottomPadding: 7 * u
    background: Rectangle {
        implicitHeight: 34 * f.u
        radius: 4 * f.u
        color: f.enabled ? MLTheme.tile : MLTheme.panelSolid
        border.width: f.activeFocus ? 2 : 1
        border.color: f.activeFocus ? MLTheme.accent : MLTheme.line
    }
}
