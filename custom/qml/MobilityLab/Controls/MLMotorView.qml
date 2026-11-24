import QtQuick

import QGroundControl
import QGroundControl.Controls

// Motor / ESC overview for multirotors and VTOLs (ESC_STATUS / ESC_INFO):
// one column per motor with an RPM bar, so a weak or stopped motor stands out.
Item {
    id: root

    property var vehicle

    readonly property var _escs:    vehicle ? vehicle.escs : null
    readonly property int _count:   (_escs && _escs.count > 0) ? Math.min(_escs.count, 12) : 0
    readonly property real _maxRpm: {
        var m = 1
        for (var i = 0; i < _count; i++) {
            var e = _escs.get(i)
            if (e && e.rpm && !isNaN(e.rpm.rawValue)) m = Math.max(m, e.rpm.rawValue)
        }
        return m
    }

    visible:        _count > 0
    implicitHeight: _count > 0 ? ScreenTools.defaultFontPixelHeight * 4.6 : 0

    Row {
        anchors.fill:   parent
        spacing:        ScreenTools.defaultFontPixelWidth * 0.6

        Repeater {
            model: root._count

            Item {
                readonly property var  _esc:    root._escs.get(index)
                readonly property real _rpm:    (_esc && _esc.rpm && !isNaN(_esc.rpm.rawValue)) ? _esc.rpm.rawValue : 0
                readonly property bool _fail:   _esc && _esc.failureFlags && _esc.failureFlags.rawValue > 0

                width:  (root.width - (root._count - 1) * ScreenTools.defaultFontPixelWidth * 0.6) / Math.max(1, root._count)
                height: root.height

                Rectangle {
                    id:                         track
                    anchors.horizontalCenter:   parent.horizontalCenter
                    anchors.top:                parent.top
                    anchors.bottom:             label.top
                    anchors.bottomMargin:       ScreenTools.defaultFontPixelHeight * 0.2
                    width:                      Math.min(parent.width * 0.6, ScreenTools.defaultFontPixelWidth * 2.2)
                    radius:                     width / 3
                    color:                      MLTheme.tile

                    Rectangle {
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.bottom: parent.bottom
                        height:         parent.height * Math.min(1, _rpm / root._maxRpm)
                        radius:         parent.radius
                        color:          _fail ? MLTheme.warning : MLTheme.accent
                        Behavior on height { NumberAnimation { duration: 200 } }
                    }
                }
                QGCLabel {
                    id:                         label
                    anchors.horizontalCenter:   parent.horizontalCenter
                    anchors.bottom:             parent.bottom
                    text:                       "M" + (index + 1)
                    color:                      _fail ? MLTheme.warning : MLTheme.label
                    font.pointSize:             ScreenTools.smallFontPointSize
                }
            }
        }
    }
}
