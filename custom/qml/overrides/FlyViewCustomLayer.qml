// MobilityLab GCS: the console panels are laid out by the FlyView override,
// so the map's custom layer only passes QGC's tool insets through.
import QtQuick

import QGroundControl
import QGroundControl.Controls

Item {
    property var parentToolInsets
    property var totalToolInsets:   parentToolInsets
    property var mapControl
}
