// MobilityLab GCS: slim tool strip. Takeoff / Land / RTL / Pause live in the bottom command bar,
// so they are removed here to avoid two places doing the same thing.
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.Viewer3D

ToolStripActionList {
    id: _root

    signal displayPreFlightChecklist

    model: [
        PreFlightCheckListShowAction { onTriggered: displayPreFlightChecklist() },
        FlyViewAdditionalActionsButton { },
        FlyViewGripperButton { },
        Viewer3DShowAction { }
    ]
}
