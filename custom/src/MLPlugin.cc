#include "MLPlugin.h"
#include "TandemTelemetry.h"
#include "MLAcactRuntime.h"
#include "MLFlightRecords.h"
#include "MLSystem.h"
#include "MLFlightAnalysis.h"
#include "MLUi.h"
#include "MLMapService.h"
#include "MLDemo.h"

#ifndef ML_GCS_VERSION
#define ML_GCS_VERSION "dev"
#endif

#include "AppSettings.h"
#include "MissionManager.h"
#include "Vehicle.h"
#include "Fact.h"
#include "FactMetaData.h"
#include "FlightMapSettings.h"
#include "QGCApplication.h"
#include "QGCLoggingCategory.h"
#include "QGCPalette.h"

#include <QGuiApplication>
#include <QScreen>
#include "SettingsManager.h"

#include <QtCore/QApplicationStatic>
#include <QtCore/QFile>
#include <QtCore/QLocale>
#include <QtCore/QSettings>
#include <QtCore/QTimer>
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
            // VWorld key: not in the source (public repository). Built in only when the build passes
            // -DML_VWORLD_KEY=...; otherwise the operator enters it once in Settings › General › VWorld.
#ifdef ML_VWORLD_KEY
            metaData.setRawDefaultValue(QStringLiteral(ML_VWORLD_KEY));
#endif
        } else if (metaData.name() == AppSettings::uiScalePercentName) {
            // Default UI scale from the primary screen's logical size (Qt already applies the OS DPI
            // setting): QHD and 4K panels left at 100 % Windows scaling get larger text by default.
            // The operator can still change it in Settings; a stored value always wins.
            int pct = 100;
            if (const QScreen *scr = QGuiApplication::primaryScreen()) {
                const int h = scr->size().height();
                pct = h >= 2000 ? 150 : (h >= 1400 ? 120 : 100);
            }
            metaData.setRawDefaultValue(pct);
        } else if (metaData.name() == AppSettings::savePathName && qEnvironmentVariableIsSet("MLGCS_PORTABLE_DIR")) {
            // portable build: logs, missions, maps cache next to the program (see patches/0004)
            metaData.setRawDefaultValue(qEnvironmentVariable("MLGCS_PORTABLE_DIR") + QStringLiteral("/data/MobilityLabGCS"));
        }
    } else if (settingsGroup == FlightMapSettings::settingsGroup) {
        if (metaData.name() == FlightMapSettings::mapProviderName) {
            // VWorld needs a key (and serves Korean IPs only): default to it only when one is built in,
            // otherwise Esri imagery, which works anywhere without a key.
#ifdef ML_VWORLD_KEY
            metaData.setRawDefaultValue(QStringLiteral("VWorld"));
#else
            metaData.setRawDefaultValue(QStringLiteral("Esri"));
#endif
        } else if (metaData.name() == FlightMapSettings::mapTypeName) {
#ifdef ML_VWORLD_KEY
            metaData.setRawDefaultValue(QStringLiteral("Satellite Map"));
#else
            metaData.setRawDefaultValue(QStringLiteral("World Satellite"));
#endif
        }
    }
}

/*---------------------------------------------------------------------------*/
/* Palette: MOBILITY LAB design system, night (QGC "Dark") and day (QGC      */
/* "Light") themes. Same values as MLTheme.qml so QGC's own pages (plan,     */
/* setup, settings, dialogs) match the console in both themes.               */
/*---------------------------------------------------------------------------*/

namespace {
struct PaletteRow { const char *name; const char *dayOn; const char *dayOff; const char *nightOn; const char *nightOff; };
// name, day enabled, day disabled, night enabled, night disabled
const PaletteRow kPalette[] = {
    {"window",              "#F7F8FA", "#F7F8FA", "#0C1014", "#0C1014"},
    {"windowTransparent",   "#F2FFFFFF", "#F2FFFFFF", "#EE0C1014", "#EE0C1014"},
    {"windowShade",         "#E9ECEF", "#E9ECEF", "#141A20", "#141A20"},
    {"windowShadeDark",     "#DDE2E7", "#DDE2E7", "#07090C", "#07090C"},
    {"windowShadeLight",    "#8A949E", "#AAB4BE", "#66707A", "#36404A"},
    {"text",                "#14181C", "#8A949E", "#ECEBE7", "#66707A"},
    {"warningText",         "#C8141C", "#C8141C", "#FF5F55", "#FF5F55"},
    {"button",              "#FFFFFF", "#F3F5F7", "#141A20", "#10151A"},
    {"buttonBorder",        "#AAB4BE", "#D3D9DF", "#36404A", "#222931"},
    {"buttonText",          "#14181C", "#8A949E", "#ECEBE7", "#66707A"},
    {"buttonHighlight",     "#0067A8", "#E4E8EC", "#1E5A78", "#141A20"},
    {"buttonHighlightText", "#FFFFFF", "#8A949E", "#FFFFFF", "#66707A"},
    {"primaryButton",       "#0067A8", "#D3D9DF", "#5CC4F0", "#222931"},
    {"primaryButtonText",   "#FFFFFF", "#8A949E", "#04121A", "#66707A"},
    {"textField",           "#FFFFFF", "#F3F5F7", "#07090C", "#10151A"},
    {"textFieldText",       "#14181C", "#8A949E", "#ECEBE7", "#66707A"},
    {"mapButton",           "#F2FFFFFF", "#D3D9DF", "#EE0C1014", "#36404A"},
    {"mapButtonHighlight",  "#0067A8", "#D3D9DF", "#5CC4F0", "#36404A"},
    {"mapIndicator",        "#0067A8", "#D3D9DF", "#5CC4F0", "#36404A"},
    {"mapIndicatorChild",   "#5A8DB5", "#D3D9DF", "#2C6E88", "#36404A"},
    {"colorGreen",          "#0B7A3B", "#0B7A3B", "#6FD394", "#6FD394"},
    {"colorYellow",         "#8A6D00", "#8A6D00", "#F2D04A", "#F2D04A"},
    {"colorYellowGreen",    "#557A10", "#557A10", "#B9DE6A", "#B9DE6A"},
    {"colorOrange",         "#9A5B00", "#9A5B00", "#F5B83A", "#F5B83A"},
    {"colorRed",            "#C8141C", "#C8141C", "#FF5F55", "#FF5F55"},
    {"colorBlue",           "#0067A8", "#0067A8", "#5CC4F0", "#5CC4F0"},
    {"colorGrey",           "#56616C", "#56616C", "#C2C8CF", "#C2C8CF"},
    {"alertBackground",     "#FFE1DF", "#FFE1DF", "#3A0F0E", "#3A0F0E"},
    {"alertBorder",         "#C8141C", "#C8141C", "#8C3530", "#8C3530"},
    {"alertText",           "#14181C", "#14181C", "#FFFFFF", "#FFFFFF"},
    {"missionItemEditor",   "#EEF3F8", "#F3F5F7", "#141A20", "#10151A"},
    {"toolStripHoverColor", "#E4E8EC", "#F3F5F7", "#1A2129", "#141A20"},
    {"statusFailedText",    "#C8141C", "#8A949E", "#FF5F55", "#66707A"},
    {"statusPassedText",    "#0B7A3B", "#8A949E", "#6FD394", "#66707A"},
    {"statusPendingText",   "#9A5B00", "#8A949E", "#F5B83A", "#66707A"},
    {"toolbarBackground",   "#F7FFFFFF", "#F7FFFFFF", "#F20C1014", "#F20C1014"},
    {"groupBorder",         "#D3D9DF", "#E3E7EB", "#222931", "#171D23"},
    {"modifiedParamValue",  "#9A5B00", "#9A5B00", "#F5B83A", "#F5B83A"},
    {"brandingPurple",      "#D80E18", "#D80E18", "#D80E18", "#D80E18"},
    {"brandingBlue",        "#D80E18", "#D80E18", "#D80E18", "#D80E18"},
    {"mapMissionTrajectory","#0067A8", "#0067A8", "#5CC4F0", "#5CC4F0"},
    {"toolStripFGColor",    "#14181C", "#8A949E", "#ECEBE7", "#66707A"},
    {"hoverColor",          "#E4E8EC", "#E4E8EC", "#1A2129", "#1A2129"},
    {"surveyPolygonInterior","#0067A8", "#0067A8", "#5CC4F0", "#5CC4F0"},
    {"surveyPolygonTerrainCollision","#C8141C", "#C8141C", "#FF5F55", "#FF5F55"},
};
}

void MLPlugin::paletteOverride(const QString &colorName, QGCPalette::PaletteColorInfo_t &colorInfo)
{
    for (const PaletteRow &r : kPalette) {
        if (colorName == QLatin1StringView(r.name)) {
            colorInfo[QGCPalette::Light][QGCPalette::ColorGroupEnabled]  = QColor(QLatin1StringView(r.dayOn));
            colorInfo[QGCPalette::Light][QGCPalette::ColorGroupDisabled] = QColor(QLatin1StringView(r.dayOff));
            colorInfo[QGCPalette::Dark][QGCPalette::ColorGroupEnabled]   = QColor(QLatin1StringView(r.nightOn));
            colorInfo[QGCPalette::Dark][QGCPalette::ColorGroupDisabled]  = QColor(QLatin1StringView(r.nightOff));
            return;
        }
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
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlAnalysis"), new MLFlightAnalysis(this));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlVersion"), QStringLiteral(ML_GCS_VERSION));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlMap"), new MLMapService(this));
    // built-in demo (simulated vehicles on an in-process link; real links blocked while it runs)
    auto *demo = new MLDemo(this);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlDemo"), demo);
    // flight records (v1.2): every flight, real and demo kept apart
    auto *records = new MLFlightRecords(this);
    records->attach(_acact, demo);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlRecords"), records);
    // backup / restore, diagnostics, abnormal-exit flag, update check
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlSystem"), new MLSystem(this));
    // CI / exhibition: MLGCS_DEMO=single|duo|trio starts the demo at launch
    if (qEnvironmentVariableIsSet("MLGCS_DEMO")) {
        const QString sc = qEnvironmentVariable("MLGCS_DEMO");
        const int delayMs = qEnvironmentVariableIsSet("MLGCS_DEMO_DELAY_MS") ? qEnvironmentVariableIntValue("MLGCS_DEMO_DELAY_MS") : 4000;
        QTimer::singleShot(delayMs, demo, [demo, sc]() {
            if (!demo->start(sc)) {
                qWarning().noquote() << "MLDEMO blocked" << demo->startBlockReason();
            }
        });
        // CI: MLGCS_DEMO_SECONDS ends the demo after that many seconds (separation test: real links allowed again)
        const int secs = qEnvironmentVariableIntValue("MLGCS_DEMO_SECONDS");
        if (secs > 0) {
            QTimer::singleShot(4000 + secs * 1000, demo, [demo]() { demo->stop(); });
        }
    }
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTour"), qEnvironmentVariable("ML_TOUR") == QStringLiteral("1"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlDemoAuto"), qEnvironmentVariable("MLGCS_DEMO_AUTO") == QStringLiteral("1"));
    // Korean / English for the MobilityLab UI (custom/i18n/en.json)
    auto *ui = new MLUi(this);
    ui->attach(_qmlEngine);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlUi"), ui);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestAcact"),
                                                  qEnvironmentVariable("ML_TEST_ACACT") == QStringLiteral("1"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestAcactCase"),
                                                  qEnvironmentVariableIsSet("ML_TEST_ACACT_CASE") ? qEnvironmentVariable("ML_TEST_ACACT_CASE") : QStringLiteral("s7duo"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestPlanDir"), qEnvironmentVariable("ML_TEST_PLAN_DIR"));
    // SITL: cycle the screen mode during the flight (case "modes")
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlPerf"), qEnvironmentVariable("ML_PERF") == QStringLiteral("1"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlPerfModes"), qEnvironmentVariable("ML_PERF_MODES") == QStringLiteral("1"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlNoOnboarding"), qEnvironmentVariable("MLGCS_NO_ONBOARDING") == QStringLiteral("1"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlDemoRepeat"), qEnvironmentVariable("MLGCS_DEMO_REPEAT") == QStringLiteral("1"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTestUiModes"), qEnvironmentVariable("ML_TEST_UI_MODES") == QStringLiteral("1"));
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
