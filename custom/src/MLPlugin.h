#pragma once

#include <QtCore/QLoggingCategory>
#include <QtQml/QQmlAbstractUrlInterceptor>

#include "QGCCorePlugin.h"
#include "QGCOptions.h"

class MLOptions;
class MLPlugin;
class TandemTelemetry;
class MLGuardLink;
class QQmlApplicationEngine;

Q_DECLARE_LOGGING_CATEGORY(MLPluginLog)

/// Fly view options for the tandem helicopter GCS.
class MLFlyViewOptions : public QGCFlyViewOptions
{
    Q_OBJECT

public:
    explicit MLFlyViewOptions(MLOptions *options, QObject *parent = nullptr);

    /// The right-hand vehicle panel includes its own flight instrument (PFD),
    /// so QGC's bottom-right attitude/compass widget is not shown.
    bool showInstrumentPanel() const final { return false; }
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

/// Small helpers the console needs that QGC does not expose to QML.
class MLTools : public QObject
{
    Q_OBJECT

public:
    explicit MLTools(QObject *parent = nullptr) : QObject(parent) {}

    /// Read the mission back from the vehicle so the fly view shows what is
    /// on board (e.g. after another GCS or a companion computer changed it).
    Q_INVOKABLE void reloadMission(QObject *vehicle);
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
    MLTools *_tools = nullptr;
    MLGuardLink *_guard = nullptr;
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
