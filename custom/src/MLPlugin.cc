#include "MLPlugin.h"
#include "TandemTelemetry.h"
#include "MLAcactRuntime.h"

#include "AppSettings.h"
#include "MissionManager.h"
#include "Vehicle.h"
#include "Fact.h"
#include "FactMetaData.h"
#include "FlightMapSettings.h"
#include "QGCApplication.h"
#include "QGCLoggingCategory.h"
#include "QGCPalette.h"
#include "SettingsManager.h"

#include <QtCore/QApplicationStatic>
#include <QtCore/QFile>
#include <QtCore/QLocale>
#include <QtCore/QSettings>
#include <QtCore/QSignalBlocker>
#include <QtGui/QFontDatabase>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>

QGC_LOGGING_CATEGORY(MLPluginLog, "MobilityLab.Plugin")

Q_APPLICATION_STATIC(MLPlugin, _mlPluginInstance);

/*===========================================================================*/

MLFlyViewOptions::MLFlyViewOptions(MLOptions *options, QObject *parent)
    : QGCFlyViewOptions(options, parent)
{
}

MLOptions::MLOptions(MLPlugin *plugin, QObject *parent)
    : QGCOptions(parent)
    , _flyViewOptions(new MLFlyViewOptions(this, this))
{
    Q_UNUSED(plugin);
}

/*===========================================================================*/

MLPlugin::MLPlugin(QObject *parent)
    : QGCCorePlugin(parent)
    , _options(new MLOptions(this, this))
    , _tandem(new TandemTelemetry(this))
    , _tools(new MLTools(this))
{
    // Field operators get the simple UI; Advanced mode is still reachable from settings.
    _showAdvancedUI = false;
}

void MLPlugin::init()
{
    QGCCorePlugin::init();

    // Console typefaces (SIL OFL): IBM Plex Sans KR for text, IBM Plex Mono for numbers
    for (const char *font : { ":/MobilityLab/fonts/IBMPlexSansKR-Regular.ttf", ":/MobilityLab/fonts/IBMPlexSansKR-SemiBold.ttf",
                              ":/MobilityLab/fonts/IBMPlexMono-Regular.ttf", ":/MobilityLab/fonts/IBMPlexMono-Medium.ttf" }) {
        if (QFontDatabase::addApplicationFont(QString::fromLatin1(font)) < 0) {
            qCWarning(MLPluginLog) << "Font not loaded:" << font;
        }
    }

    // QGC reads the language straight from QSettings before plugins load, so a
    // metadata default is not enough. Switch to Korean once on first start;
    // after that the operator's own choice in Application Settings is kept.
    QSettings settings;
    const QString key = QStringLiteral("MobilityLab/koreanDefaultApplied");
    if (!settings.value(key, false).toBool()) {
        settings.setValue(key, true);
        settings.setValue(QString::fromLatin1(AppSettings::qLocaleLanguageName), static_cast<int>(QLocale::Korean));

        // Keep the Fact in step without its "restart application" prompt; the
        // value is already saved above and the language is applied right away.
        Fact *language = SettingsManager::instance()->appSettings()->qLocaleLanguage();
        if (language) {
            const QSignalBlocker blocker(language);
            language->setRawValue(static_cast<int>(QLocale::Korean));
        }
        if (qgcApp()) {
            qgcApp()->setLanguage();    // loads Korean translations and the NanumGothic font
        }
    }
}

QGCCorePlugin *MLPlugin::instance()
{
    return _mlPluginInstance();
}

bool MLPlugin::mavlinkMessage(Vehicle *vehicle, LinkInterface *link, const mavlink_message_t &message)
{
    Q_UNUSED(link);
    _tandem->handleMessage(vehicle, message);
    return true;    // never swallow messages, QGC handles them as usual
}

void MLPlugin::adjustSettingMetaData(const QString &settingsGroup, FactMetaData &metaData, bool &userVisible)
{
    QGCCorePlugin::adjustSettingMetaData(settingsGroup, metaData, userVisible);

    if (settingsGroup == AppSettings::settingsGroup) {
        if (metaData.name() == AppSettings::vworldTokenName) {
            // MobilityLab VWorld key (carried over from the previous GCS build).
            metaData.setRawDefaultValue(QStringLiteral("FB59EEB2-7C61-3661-BEC9-630307354042"));
        } else if (metaData.name() == AppSettings::savePathName && qEnvironmentVariableIsSet("MLGCS_PORTABLE_DIR")) {
            // portable build: logs, missions, maps cache next to the program (see patches/0004)
            metaData.setRawDefaultValue(qEnvironmentVariable("MLGCS_PORTABLE_DIR") + QStringLiteral("/data/MobilityLabGCS"));
        }
    } else if (settingsGroup == FlightMapSettings::settingsGroup) {
        if (metaData.name() == FlightMapSettings::mapProviderName) {
            metaData.setRawDefaultValue(QStringLiteral("VWorld"));
        } else if (metaData.name() == FlightMapSettings::mapTypeName) {
            metaData.setRawDefaultValue(QStringLiteral("Satellite Map"));
        }
    }
}

/*---------------------------------------------------------------------------*/
/* Palette: graphite night theme with avionics status colours.               */
/* Only the dark (indoor) theme is restyled; the light theme stays QGC's     */
/* high-contrast outdoor palette for use in direct sunlight.                  */
/*---------------------------------------------------------------------------*/

namespace {
void setDark(QGCPalette::PaletteColorInfo_t &info, const char *enabled, const char *disabled = nullptr)
{
    info[QGCPalette::Dark][QGCPalette::ColorGroupEnabled]  = QColor(QLatin1StringView(enabled));
    info[QGCPalette::Dark][QGCPalette::ColorGroupDisabled] = QColor(QLatin1StringView(disabled ? disabled : enabled));
}
void setBoth(QGCPalette::PaletteColorInfo_t &info, const char *light, const char *dark)
{
    info[QGCPalette::Light][QGCPalette::ColorGroupEnabled]  = QColor(QLatin1StringView(light));
    info[QGCPalette::Light][QGCPalette::ColorGroupDisabled] = QColor(QLatin1StringView(light));
    info[QGCPalette::Dark][QGCPalette::ColorGroupEnabled]   = QColor(QLatin1StringView(dark));
    info[QGCPalette::Dark][QGCPalette::ColorGroupDisabled]  = QColor(QLatin1StringView(dark));
}
}

void MLPlugin::paletteOverride(const QString &colorName, QGCPalette::PaletteColorInfo_t &colorInfo)
{
    // Console palette (see MLTheme.qml). Dark theme only, except status and
    // map colours, which are set for both themes so the meaning never changes.
    if (colorName == QStringLiteral("window")) {
        setDark(colorInfo, "#0A0D10");
    } else if (colorName == QStringLiteral("windowTransparent")) {
        setDark(colorInfo, "#E60A0D10");
    } else if (colorName == QStringLiteral("windowShade")) {
        setDark(colorInfo, "#11161B");
    } else if (colorName == QStringLiteral("windowShadeDark")) {
        setDark(colorInfo, "#07090B");
    } else if (colorName == QStringLiteral("windowShadeLight")) {
        setDark(colorInfo, "#4A535C", "#2A3038");
    } else if (colorName == QStringLiteral("text")) {
        setDark(colorInfo, "#E6E4DE", "#4A535C");
    } else if (colorName == QStringLiteral("warningText")) {
        setDark(colorInfo, "#FF5A52");
    } else if (colorName == QStringLiteral("button")) {
        setDark(colorInfo, "#11161B", "#0D1115");
    } else if (colorName == QStringLiteral("buttonBorder")) {
        setDark(colorInfo, "#2A3038", "#1B2026");
    } else if (colorName == QStringLiteral("buttonText")) {
        setDark(colorInfo, "#E6E4DE", "#4A535C");
    } else if (colorName == QStringLiteral("buttonHighlight")) {
        setDark(colorInfo, "#1E5A72", "#11161B");
    } else if (colorName == QStringLiteral("buttonHighlightText")) {
        setDark(colorInfo, "#F2F1EE", "#4A535C");
    } else if (colorName == QStringLiteral("primaryButton")) {
        setDark(colorInfo, "#5BC0EB", "#1B2026");
    } else if (colorName == QStringLiteral("primaryButtonText")) {
        setDark(colorInfo, "#07090B", "#4A535C");
    } else if (colorName == QStringLiteral("textField")) {
        setDark(colorInfo, "#07090B", "#0D1115");
    } else if (colorName == QStringLiteral("textFieldText")) {
        setDark(colorInfo, "#E6E4DE", "#4A535C");
    } else if (colorName == QStringLiteral("mapButton")) {
        setDark(colorInfo, "#E60A0D10", "#2A3038");
    } else if (colorName == QStringLiteral("mapButtonHighlight")) {
        setDark(colorInfo, "#5BC0EB", "#2A3038");
    } else if (colorName == QStringLiteral("mapIndicator")) {
        setDark(colorInfo, "#5BC0EB", "#2A3038");
    } else if (colorName == QStringLiteral("mapIndicatorChild")) {
        setDark(colorInfo, "#2C6E88", "#2A3038");
    } else if (colorName == QStringLiteral("colorGreen")) {
        setBoth(colorInfo, "#0a8a3e", "#6FD08C");
    } else if (colorName == QStringLiteral("colorYellow")) {
        setBoth(colorInfo, "#a2a200", "#F0D04A");
    } else if (colorName == QStringLiteral("colorOrange")) {
        setBoth(colorInfo, "#b86e00", "#F0B232");
    } else if (colorName == QStringLiteral("colorRed")) {
        setBoth(colorInfo, "#c41d24", "#FF5A52");
    } else if (colorName == QStringLiteral("colorBlue")) {
        setBoth(colorInfo, "#0b6e86", "#5BC0EB");
    } else if (colorName == QStringLiteral("colorGrey")) {
        setBoth(colorInfo, "#808080", "#AEB4BB");
    } else if (colorName == QStringLiteral("alertBackground")) {
        setBoth(colorInfo, "#120C0D", "#120C0D");
    } else if (colorName == QStringLiteral("alertBorder")) {
        setBoth(colorInfo, "#6B3430", "#6B3430");
    } else if (colorName == QStringLiteral("alertText")) {
        setBoth(colorInfo, "#F2F1EE", "#F2F1EE");
    } else if (colorName == QStringLiteral("missionItemEditor")) {
        setDark(colorInfo, "#11161B", "#0D1115");
    } else if (colorName == QStringLiteral("toolStripHoverColor")) {
        setDark(colorInfo, "#1B2A33", "#11161B");
    } else if (colorName == QStringLiteral("toolbarBackground")) {
        setDark(colorInfo, "#F20A0D10");
    } else if (colorName == QStringLiteral("groupBorder")) {
        setDark(colorInfo, "#1B2026");
    } else if (colorName == QStringLiteral("brandingBlue")) {
        setBoth(colorInfo, "#D80E18", "#D80E18");
    } else if (colorName == QStringLiteral("mapMissionTrajectory")) {
        setBoth(colorInfo, "#5BC0EB", "#5BC0EB");
    } else if (colorName == QStringLiteral("toolStripFGColor")) {
        setBoth(colorInfo, "#AEB4BB", "#E6E4DE");
    }
}

/*---------------------------------------------------------------------------*/

QQmlApplicationEngine *MLPlugin::createQmlApplicationEngine(QObject *parent)
{
    _qmlEngine = QGCCorePlugin::createQmlApplicationEngine(parent);
    _qmlEngine->addImportPath(QStringLiteral("qrc:/qml"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTandem"), _tandem);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTools"), _tools);
    // ACACT guard built into the GCS. Created here (after the vehicle manager exists).
    if (!_acact) {
        _acact = new MLAcactRuntime(this);
    }
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlGuard"), _acact);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlAcact"), _acact);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestAcact"),
                                                  qEnvironmentVariable("ML_TEST_ACACT") == QStringLiteral("1"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestAcactCase"),
                                                  qEnvironmentVariableIsSet("ML_TEST_ACACT_CASE") ? qEnvironmentVariable("ML_TEST_ACACT_CASE") : QStringLiteral("s7duo"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestPlanDir"), qEnvironmentVariable("ML_TEST_PLAN_DIR"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestAcactN"),
                                                  qEnvironmentVariableIsSet("ML_TEST_ACACT_N") ? qEnvironmentVariableIntValue("ML_TEST_ACACT_N") : 2);
    // CI only: ML_TEST_SETPOINTS=1 makes the 목표 조정 panel run its scripted SITL check
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestSetpoints"),
                                                  qEnvironmentVariable("ML_TEST_SETPOINTS") == QStringLiteral("1"));

    _urlInterceptor = new MLOverrideInterceptor();
    _qmlEngine->addUrlInterceptor(_urlInterceptor);

    return _qmlEngine;
}

void MLPlugin::destroyQmlApplicationEngine(QQmlApplicationEngine *qmlEngine)
{
    if (qmlEngine && (qmlEngine == _qmlEngine)) {
        qmlEngine->removeUrlInterceptor(_urlInterceptor);
        delete _urlInterceptor;
        _urlInterceptor = nullptr;
        _qmlEngine = nullptr;
    }

    QGCCorePlugin::destroyQmlApplicationEngine(qmlEngine);
}

/*===========================================================================*/

QUrl MLOverrideInterceptor::intercept(const QUrl &url, QQmlAbstractUrlInterceptor::DataType type)
{
    switch (type) {
    case QQmlAbstractUrlInterceptor::QmlFile:
    case QQmlAbstractUrlInterceptor::UrlString:
        if (url.scheme() == QStringLiteral("qrc")) {
            const QString overrideRes = QStringLiteral(":/Custom%1").arg(url.path());
            if (QFile::exists(overrideRes)) {
                QUrl result;
                result.setScheme(QStringLiteral("qrc"));
                result.setPath(overrideRes.mid(1));
                return result;
            }
        }
        break;
    default:
        break;
    }
    return url;
}

/*===========================================================================*/

void MLTools::reloadMission(QObject *vehicleObject)
{
    Vehicle *vehicle = qobject_cast<Vehicle *>(vehicleObject);
    if (!vehicle || !vehicle->missionManager()) {
        return;
    }
    if (vehicle->missionManager()->inProgress()) {
        qCDebug(MLPluginLog) << "reloadMission: transfer already in progress";
        return;
    }
    vehicle->missionManager()->loadFromVehicle();
}
