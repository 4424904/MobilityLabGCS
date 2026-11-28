// MobilityLab GCS — product services (v1.2): settings backup / restore, diagnostic report,
// abnormal-exit detection, update check with integrity verification.
//
// Nothing here touches a vehicle. The update is only offered: the operator decides, the download
// is verified against the release's SHA256SUMS.txt, and installing is refused while any vehicle is
// armed. User data (settings, missions, records, logs) live outside the program folder and are kept
// by the installer.
#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantMap>

class QNetworkAccessManager;
class QNetworkReply;

class MLSystem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         previousCrash   READ previousCrash  CONSTANT)          // last session did not end normally
    Q_PROPERTY(QString      updateState     READ updateState    NOTIFY updateChanged) // idle · checking · none · available · downloading · verified · failed
    Q_PROPERTY(QString      updateText      READ updateText     NOTIFY updateChanged)
    Q_PROPERTY(QString      latestVersion   READ latestVersion  NOTIFY updateChanged)
    Q_PROPERTY(QString      releaseUrl      READ releaseUrl     NOTIFY updateChanged)
    Q_PROPERTY(double       progress        READ progress       NOTIFY updateChanged)

public:
    explicit MLSystem(QObject *parent = nullptr);
    ~MLSystem() override;

    bool previousCrash() const { return _prevCrash; }
    QString updateState() const { return _state; }
    QString updateText() const { return _text; }
    QString latestVersion() const { return _latest; }
    QString releaseUrl() const { return _releaseUrl; }
    double progress() const { return _progress; }

    /// copies every setting (QGC + MobilityLab: layouts, favourites, profiles, preferences) to an .ini file
    Q_INVOKABLE QString backupSettings(const QString &path = QString());
    /// reads such a file back; takes effect after a restart. Returns "" or the reason it failed.
    Q_INVOKABLE QString restoreSettings(const QString &path);
    /// a text report for support: versions, OS, graphics, folders, settings (secrets removed), crash flag
    Q_INVOKABLE QString writeDiagnostics(const QString &path = QString());
    Q_INVOKABLE QString dataDir() const;

    /// GitHub releases of this product (public API, no key)
    Q_INVOKABLE void checkForUpdate();
    /// Windows: download the newer installer and verify its SHA256 against SHA256SUMS.txt
    Q_INVOKABLE void downloadUpdate();
    /// run the verified installer and close the GCS — refused while any vehicle is armed
    Q_INVOKABLE QString installUpdate();

    static int compareVersions(const QString &a, const QString &b);

signals:
    void updateChanged();

private:
    void _set(const QString &state, const QString &text);
    void _markClean();

    QNetworkAccessManager *_nam = nullptr;
    bool _prevCrash = false;
    QString _state = QStringLiteral("idle"), _text, _latest, _releaseUrl, _assetUrl, _assetName, _sumsUrl, _file;
    double _progress = 0;
};
