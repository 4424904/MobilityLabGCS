#pragma once

#include <QtCore/QLoggingCategory>
#include <QtQml/QQmlAbstractUrlInterceptor>

#include "QGCCorePlugin.h"
#include "QGCOptions.h"

class MLOptions;
class MLPlugin;
class TandemTelemetry;
class QQmlApplicationEngine;

Q_DECLARE_LOGGING_CATEGORY(MLPluginLog)

/// Fly view options for the tandem helicopter GCS.
class MLFlyViewOptions : public QGCFlyViewOptions
{
    Q_OBJECT

public:
    explicit MLFlyViewOptions(MLOptions *options, QObject *parent = nullptr);

    /// One aircraft per GCS. Keeps the UI simple; the fleet list is not shown.
    bool showMultiVehicleList() const final { return false; }
};

class MLOptions : public QGCOptions
{
    Q_OBJECT

public:
    explicit MLOptions(MLPlugin *plugin, QObject *parent = nullptr);

    QGCFlyViewOptions *flyViewOptions() const final { return _flyViewOptions; }

private:
    MLFlyViewOptions *_flyViewOptions = nullptr;
};

/// MobilityLab GCS core plugin.
///  - Branding, palette and Korean defaults
///  - Tandem helicopter telemetry (engine / rotors / fuel / power) exposed to QML
///  - QML overrides for the fly view (see custom.qrc, prefix /Custom/qml)
class MLPlugin : public QGCCorePlugin
{
    Q_OBJECT

public:
    explicit MLPlugin(QObject *parent = nullptr);

    static QGCCorePlugin *instance();

    void init() final;
    QGCOptions *options() final { return _options; }
    void adjustSettingMetaData(const QString &settingsGroup, FactMetaData &metaData, bool &userVisible) final;
    void paletteOverride(const QString &colorName, QGCPalette::PaletteColorInfo_t &colorInfo) final;
    QQmlApplicationEngine *createQmlApplicationEngine(QObject *parent) final;
    void destroyQmlApplicationEngine(QQmlApplicationEngine *qmlEngine) final;
    bool mavlinkMessage(Vehicle *vehicle, LinkInterface *link, const mavlink_message_t &message) final;
    bool showInitialSetupVehiclePreferences() const final { return false; }
    bool showInitialSetupMeasurementUnits() const final { return false; }

private:
    MLOptions *_options = nullptr;
    TandemTelemetry *_tandem = nullptr;
    QQmlApplicationEngine *_qmlEngine = nullptr;
    class MLOverrideInterceptor *_urlInterceptor = nullptr;
};

/// Redirects qrc:/qml/... loads to qrc:/Custom/qml/... when an override exists.
class MLOverrideInterceptor : public QQmlAbstractUrlInterceptor
{
public:
    MLOverrideInterceptor() = default;
    QUrl intercept(const QUrl &url, QQmlAbstractUrlInterceptor::DataType type) final;
};
