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
# every QML file of the module (new components are picked up without editing this list)
file(GLOB ML_QML_FILES CONFIGURE_DEPENDS ${ML_QML_DIR}/*.qml)
list(SORT ML_QML_FILES)
set_source_files_properties(${ML_QML_DIR}/MLTheme.qml ${ML_QML_DIR}/MLState.qml ${ML_QML_DIR}/MLReadiness.qml ${ML_QML_DIR}/MLAcactStatus.qml ${ML_QML_DIR}/MLProfiles.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
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
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLUi.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLUi.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLFlightAnalysis.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLFlightAnalysis.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLFlightRecords.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLSystem.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLSystem.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLFlightRecords.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLDemo.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLDemo.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLMapService.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLMapService.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLAcactRuntime.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/MLAcactRuntime.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/acact/AcactConfig.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/acact/AcactCore.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/acact/AcactCore.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/acact/AcactMissionCheck.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/acact/AcactMissionCheck.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/acact/AcactScenarios.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/acact/AcactScenarios.h
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

file(READ ${CMAKE_CURRENT_SOURCE_DIR}/ML_VERSION.txt ML_GCS_VERSION)
string(STRIP "${ML_GCS_VERSION}" ML_GCS_VERSION)
message(STATUS "MobilityLab GCS ${ML_GCS_VERSION}")
set(CUSTOM_DEFINITIONS
    ML_GCS_VERSION="${ML_GCS_VERSION}"
    QGC_CUSTOM_BUILD
    CUSTOMHEADER="MLPlugin.h"
    CUSTOMCLASS=MLPlugin
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_QT_COMPONENTS
    Core
    Network
    CACHE INTERNAL "" FORCE
)
