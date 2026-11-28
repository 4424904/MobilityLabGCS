#include "MLUi.h"
#include "FactMetaData.h"

#include "AppSettings.h"
#include "AudioOutput.h"
#include "Fact.h"
#include "SettingsManager.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QFile>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QLocale>
#include <QtCore/QSettings>
#include <QtQml/QQmlApplicationEngine>

bool MLJsonTranslator::loadJson(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return false;
    }
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    _map.clear();
    for (auto it = o.begin(); it != o.end(); ++it) {
        const QString v = it.value().toString();
        if (!v.isEmpty() && !it.key().startsWith(QLatin1Char('_'))) {
            _map.insert(it.key(), v);
        }
    }
    return !_map.isEmpty();
}

QString MLJsonTranslator::translate(const char *, const char *sourceText, const char *, int) const
{
    // MobilityLab strings are unique in Korean, so the context is not needed
    return sourceText ? _map.value(QString::fromUtf8(sourceText)) : QString();
}

MLUi::MLUi(QObject *parent)
    : QObject(parent)
{
    _lang = QSettings().value(QStringLiteral("MobilityLab/uiLanguage"), QStringLiteral("ko")).toString() == QLatin1String("en") ? QStringLiteral("en")
                                                                                                                              : QStringLiteral("ko");
}

void MLUi::attach(QQmlApplicationEngine *engine)
{
    _engine = engine;
    _apply(false);
}

void MLUi::setLanguage(const QString &lang)
{
    const QString l = lang == QLatin1String("en") ? QStringLiteral("en") : QStringLiteral("ko");
    if (l == _lang) {
        return;
    }
    _lang = l;
    QSettings().setValue(QStringLiteral("MobilityLab/uiLanguage"), l);
    // QGC's own strings follow (its language fact reloads its translators)
    // The screen is retranslated live below, so QGC's blocking "restart application" dialog is
    // not shown; the console notes that QGC's own settings-page labels follow after a restart.
    Fact *fact = SettingsManager::instance()->appSettings()->qLocaleLanguage();
    FactMetaData *meta = fact->metaData();
    const bool reboot = meta && meta->qgcRebootRequired();
    if (meta) {
        meta->setQGCRebootRequired(false);
    }
    fact->setRawValue(l == QLatin1String("en") ? QLocale::English : QLocale::Korean);
    if (meta) {
        meta->setQGCRebootRequired(reboot);
    }
    _apply(true);
    emit languageChanged();
}

void MLUi::_apply(bool retranslate)
{
    if (_installed) {
        QCoreApplication::removeTranslator(&_tr);
        _installed = false;
    }
    if (_lang == QLatin1String("en") && (_tr.isEmpty() ? _tr.loadJson(QStringLiteral(":/MobilityLab/i18n/en.json")) : true)) {
        QCoreApplication::installTranslator(&_tr);
        _installed = true;
    }
    if (retranslate && _engine) {
        _engine->retranslate();
    }
}

void MLUi::say(const QString &text)
{
    if (!text.trimmed().isEmpty()) {
        AudioOutput::instance()->say(text);
    }
}
