# ============================================================================
# MobilityLab GCS - QGroundControl custom build overrides
# Included by QGC's top-level CMakeLists.txt before its own defaults are set.
# ============================================================================

# ----------------------------------------------------------------------------
# Application identity
# (QGC_APP_NAME is also the executable name, so keep it free of spaces.)
# ----------------------------------------------------------------------------
set(QGC_APP_NAME        "MobilityLabGCS"                                        CACHE STRING "App Name" FORCE)
set(QGC_APP_DESCRIPTION "MobilityLab Ground Control Station"                    CACHE STRING "Description" FORCE)
set(QGC_APP_COPYRIGHT   "Copyright (c) 2026 MobilityLab. Based on QGroundControl." CACHE STRING "Copyright" FORCE)
set(QGC_ORG_NAME        "MobilityLab"                                           CACHE STRING "Org Name" FORCE)
set(QGC_ORG_DOMAIN      "mobilitylab.kr"                                        CACHE STRING "Domain" FORCE)
set(QGC_PACKAGE_NAME    "kr.mobilitylab.gcs"                                    CACHE STRING "Package Name" FORCE)
set(QGC_ANDROID_PACKAGE_NAME "kr.mobilitylab.gcs"                               CACHE STRING "Android package identifier" FORCE)

# ----------------------------------------------------------------------------
# Icons and installer graphics
# ----------------------------------------------------------------------------
set(_ml_dir "${CMAKE_SOURCE_DIR}/${QGC_CUSTOM_DIR}")

if(EXISTS "${_ml_dir}/deploy/windows/MobilityLabGCS.ico")
    set(QGC_WINDOWS_ICON_PATH "${_ml_dir}/deploy/windows/MobilityLabGCS.ico" CACHE FILEPATH "Windows Icon Path" FORCE)
endif()
if(EXISTS "${_ml_dir}/deploy/windows/installheader.bmp")
    set(QGC_WINDOWS_INSTALL_HEADER_PATH "${_ml_dir}/deploy/windows/installheader.bmp" CACHE FILEPATH "Windows Install Header Path" FORCE)
endif()
if(EXISTS "${_ml_dir}/deploy/linux/MobilityLabGCS_256.png")
    set(QGC_APPIMAGE_ICON_256_PATH "${_ml_dir}/deploy/linux/MobilityLabGCS_256.png" CACHE FILEPATH "AppImage 256x256 icon path" FORCE)
endif()
if(EXISTS "${_ml_dir}/res/icons/MobilityLabLogo.svg")
    set(QGC_APPIMAGE_ICON_SCALABLE_PATH "${_ml_dir}/res/icons/MobilityLabLogo.svg" CACHE FILEPATH "AppImage SVG icon path" FORCE)
endif()

# ----------------------------------------------------------------------------
# Feature set
# Firmware is not fixed yet for the tandem helicopter (PX4 or ArduPilot), so both
# firmware plugins stay enabled. Revisit once the FCC firmware is decided.
# ----------------------------------------------------------------------------
