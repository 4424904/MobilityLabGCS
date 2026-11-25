#include "MLPlugin.h"
#include "TandemTelemetry.h"

#include "AppSettings.h"
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
{
    // Field operators get the simple UI; Advanced mode is still reachable from settings.
    _showAdvancedUI = false;
}

void MLPlugin::init()
{
    QGCCorePlugin::init();

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
    if (colorName == QStringLiteral("window")) {
        setDark(colorInfo, "#11171a");
    } else if (colorName == QStringLiteral("windowTransparent")) {
        setDark(colorInfo, "#e011171a");
    } else if (colorName == QStringLiteral("windowShade")) {
        setDark(colorInfo, "#1a2226");
    } else if (colorName == QStringLiteral("windowShadeDark")) {
        setDark(colorInfo, "#0b0f11");
    } else if (colorName == QStringLiteral("windowShadeLight")) {
        setDark(colorInfo, "#5d6e74", "#4a585d");
    } else if (colorName == QStringLiteral("text")) {
        setDark(colorInfo, "#e6ece9", "#6f7f84");
    } else if (colorName == QStringLiteral("warningText")) {
        setDark(colorInfo, "#ff5a5a");
    } else if (colorName == QStringLiteral("button")) {
        setDark(colorInfo, "#223036", "#1a2226");
    } else if (colorName == QStringLiteral("buttonBorder")) {
        setDark(colorInfo, "#3b4d54", "#2a363b");
    } else if (colorName == QStringLiteral("buttonText")) {
        setDark(colorInfo, "#e6ece9", "#6f7f84");
    } else if (colorName == QStringLiteral("buttonHighlight")) {
        setDark(colorInfo, "#1d7f95", "#223036");
    } else if (colorName == QStringLiteral("buttonHighlightText")) {
        setDark(colorInfo, "#ffffff", "#6f7f84");
    } else if (colorName == QStringLiteral("primaryButton")) {
        setDark(colorInfo, "#1d7f95", "#2a363b");
    } else if (colorName == QStringLiteral("primaryButtonText")) {
        setDark(colorInfo, "#ffffff", "#8fa0a5");
    } else if (colorName == QStringLiteral("textField")) {
        setDark(colorInfo, "#0b1114", "#1a2226");
    } else if (colorName == QStringLiteral("textFieldText")) {
        setDark(colorInfo, "#e6ece9", "#6f7f84");
    } else if (colorName == QStringLiteral("mapButton")) {
        setDark(colorInfo, "#0b1114", "#3b4d54");
    } else if (colorName == QStringLiteral("mapButtonHighlight")) {
        setDark(colorInfo, "#4fd3ea", "#3b4d54");
    } else if (colorName == QStringLiteral("mapIndicator")) {
        setDark(colorInfo, "#4fd3ea", "#3b4d54");
    } else if (colorName == QStringLiteral("mapIndicatorChild")) {
        setDark(colorInfo, "#2b7f90", "#3b4d54");
    } else if (colorName == QStringLiteral("colorGreen")) {
        setBoth(colorInfo, "#0a8a3e", "#4ccf7c");
    } else if (colorName == QStringLiteral("colorOrange")) {
        setBoth(colorInfo, "#b86e00", "#f5b331");
    } else if (colorName == QStringLiteral("colorRed")) {
        setBoth(colorInfo, "#c41d24", "#ff4f4f");
    } else if (colorName == QStringLiteral("colorBlue")) {
        setBoth(colorInfo, "#0b6e86", "#4fd3ea");
    } else if (colorName == QStringLiteral("missionItemEditor")) {
        setDark(colorInfo, "#1a2226", "#11171a");
    } else if (colorName == QStringLiteral("toolStripHoverColor")) {
        setDark(colorInfo, "#2b4a54", "#1a2226");
    } else if (colorName == QStringLiteral("toolbarBackground")) {
        setDark(colorInfo, "#e00d1215");
    } else if (colorName == QStringLiteral("groupBorder")) {
        setDark(colorInfo, "#2a363b");
    } else if (colorName == QStringLiteral("brandingBlue")) {
        setBoth(colorInfo, "#d80e18", "#d80e18");
    }
}

/*---------------------------------------------------------------------------*/

QQmlApplicationEngine *MLPlugin::createQmlApplicationEngine(QObject *parent)
{
    _qmlEngine = QGCCorePlugin::createQmlApplicationEngine(parent);
    _qmlEngine->addImportPath(QStringLiteral("qrc:/qml"));
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("mlTandem"), _tandem);
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
