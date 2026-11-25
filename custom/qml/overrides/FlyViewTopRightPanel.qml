// MobilityLab GCS: QGC's map-corner multi-vehicle panel is replaced by the
// console's 기체 (fleet) panel, so this stays hidden. Keeps the properties
// FlyViewWidgetLayer reads.
import QtQuick

import QGroundControl
import QGroundControl.Controls

Item {
    property real maximumHeight
    visible:    false
    width:      0
    height:     0
}
