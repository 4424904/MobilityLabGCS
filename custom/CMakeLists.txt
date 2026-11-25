# ============================================================================
# MobilityLab GCS - QGroundControl custom plugin
# This folder is copied to <qgc>/custom by the build workflow.
# ============================================================================

message(STATUS "MobilityLab GCS: adding custom plugin")

# ----------------------------------------------------------------------------
# Plain resources (QML overrides, config, images)
# ----------------------------------------------------------------------------
list(APPEND CUSTOM_RESOURCES ${CMAKE_CURRENT_SOURCE_DIR}/custom.qrc)
set(QGC_RESOURCES ${QGC_RESOURCES} ${CUSTOM_RESOURCES} CACHE STRING "Paths to .qrc Resources" FORCE)

set(QML_IMPORT_PATH ${QML_IMPORT_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/qml" CACHE STRING "Extra qml import paths" FORCE)

# ----------------------------------------------------------------------------
# QML module: MobilityLab.Controls (compiled by qmlcachegen at build time)
# ----------------------------------------------------------------------------
qt_add_library(MobilityLabControlsModule STATIC)

set(ML_QML_DIR ${CMAKE_CURRENT_SOURCE_DIR}/qml/MobilityLab/Controls)
set(ML_QML_FILES
    ${ML_QML_DIR}/MLTheme.qml
    ${ML_QML_DIR}/MLState.qml
    ${ML_QML_DIR}/MLText.qml
    ${ML_QML_DIR}/MLNum.qml
    ${ML_QML_DIR}/MLSection.qml
    ${ML_QML_DIR}/MLPanel.qml
    ${ML_QML_DIR}/MLPfd.qml
    ${ML_QML_DIR}/MLArcGauge.qml
    ${ML_QML_DIR}/MLMotorView.qml
    ${ML_QML_DIR}/MLFlightColumn.qml
    ${ML_QML_DIR}/MLSystemsColumn.qml
    ${ML_QML_DIR}/MLTrendTable.qml
    ${ML_QML_DIR}/MLCasList.qml
    ${ML_QML_DIR}/MLMissionList.qml
    ${ML_QML_DIR}/MLProfile.qml
    ${ML_QML_DIR}/MLFleetPanel.qml
    ${ML_QML_DIR}/MLToast.qml
    ${ML_QML_DIR}/MLEventLog.qml
    ${ML_QML_DIR}/MLAlertBanner.qml
    ${ML_QML_DIR}/MLMapHud.qml
    ${ML_QML_DIR}/MLSetpointPanel.qml
    ${ML_QML_DIR}/MLCommandBar.qml
    ${ML_QML_DIR}/MLCommandButton.qml
    ${ML_QML_DIR}/MLHoldButton.qml
)
set_source_files_properties(${ML_QML_DIR}/MLTheme.qml ${ML_QML_DIR}/MLState.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qgc_set_qt_resource_alias(${ML_QML_FILES})

qt_add_qml_module(MobilityLabControlsModule
    URI MobilityLab.Controls
    VERSION 1.0
    RESOURCE_PREFIX /qml
    QML_FILES ${ML_QML_FILES}
    NO_PLUGIN
)

# ----------------------------------------------------------------------------
# C++ sources, compiled into the main QGC target
# ----------------------------------------------------------------------------
set(CUSTOM_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLPlugin.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLPlugin.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/TandemTelemetry.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/TandemTelemetry.h
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_LIBRARIES
    MobilityLabControlsModule
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_INCLUDE_DIRECTORIES
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_DEFINITIONS
    QGC_CUSTOM_BUILD
    CUSTOMHEADER="MLPlugin.h"
    CUSTOMCLASS=MLPlugin
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_QT_COMPONENTS
    Core
    CACHE INTERNAL "" FORCE
)
