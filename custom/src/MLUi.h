// MobilityLab GCS — UI language (Korean / English) for everything MobilityLab adds.
//
// Korean is the source language of the MobilityLab strings; English comes from custom/i18n/en.json
// through MLJsonTranslator (no lrelease step needed). Switching also sets QGC's own language
// (Settings › General › Language) so the whole program changes together, then retranslates the QML.
#pragma once

#include <QtCore/QHash>
#include <QtCore/QObject>
#include <QtCore/QTranslator>

class QQmlApplicationEngine;

class MLJsonTranslator : public QTranslator
{
public:
    bool loadJson(const QString &path);
    QString translate(const char *context, const char *sourceText, const char *disambiguation = nullptr, int n = -1) const override;
    bool isEmpty() const override { return _map.isEmpty(); }

private:
    QHash<QString, QString> _map;
};

class MLUi : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)   // "ko" | "en"

public:
    explicit MLUi(QObject *parent = nullptr);
    QString language() const { return _lang; }
    void setLanguage(const QString &lang);
    void attach(QQmlApplicationEngine *engine);   // install the translator for the saved language
    /// voice alert through QGC's speech output (QGC volume and mute settings apply)
    Q_INVOKABLE void say(const QString &text);

signals:
    void languageChanged();

private:
    void _apply(bool retranslate);
    QString _lang = QStringLiteral("ko");
    MLJsonTranslator _tr;
    bool _installed = false;
    QQmlApplicationEngine *_engine = nullptr;
};
