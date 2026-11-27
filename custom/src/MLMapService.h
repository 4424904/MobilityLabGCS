#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QVariantList>

class QNetworkAccessManager;
class QNetworkReply;

/// Map services for the console (mlMap in QML):
///  - tile server check: requests one tile of the selected provider exactly as the map engine does
///    (same URL, referrer and token) and reports whether the server answers, so a blank map gets a
///    reason (no network, timeout, refused / key needed, HTTP error) instead of grey tiles;
///  - place search: coordinates (decimal, DMS, MGRS) are parsed locally; names and addresses go to
///    OpenStreetMap Nominatim (no key, one request per search, as its usage policy asks);
///  - test-site favourites, stored in the user settings.
class MLMapService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString      status      READ status         NOTIFY statusChanged)       // idle · checking · ok · error
    Q_PROPERTY(QString      statusText  READ statusText     NOTIFY statusChanged)
    Q_PROPERTY(QString      checkedType READ checkedType    NOTIFY statusChanged)
    Q_PROPERTY(int          latencyMs   READ latencyMs      NOTIFY statusChanged)
    Q_PROPERTY(bool         searching   READ searching      NOTIFY searchChanged)
    Q_PROPERTY(QVariantList results     READ results        NOTIFY searchChanged)
    Q_PROPERTY(QString      searchError READ searchError    NOTIFY searchChanged)
    Q_PROPERTY(QVariantList favorites   READ favorites      NOTIFY favoritesChanged)

public:
    explicit MLMapService(QObject *parent = nullptr);

    QString status() const { return _status; }
    QString statusText() const { return _statusText; }
    QString checkedType() const { return _checkedType; }
    int latencyMs() const { return _latency; }
    bool searching() const { return _searching; }
    QVariantList results() const { return _results; }
    QString searchError() const { return _searchError; }
    QVariantList favorites() const { return _favorites; }

    /// type: QGC map type name, e.g. "Esri World Satellite", "Google Satellite", "VWorld Satellite Map"
    Q_INVOKABLE void probe(const QString &type, double lat, double lon, int zoom);
    /// decimal "37.21, 126.83" · DMS "37°12'36\"N 126°49'51\"E" · MGRS "52S CG 07472 20354"
    Q_INVOKABLE QVariantMap parseCoordinate(const QString &text) const;
    Q_INVOKABLE void search(const QString &text, double nearLat, double nearLon);
    Q_INVOKABLE void clearSearch();
    Q_INVOKABLE void addFavorite(const QString &name, double lat, double lon, double zoom, const QString &note = QString());
    Q_INVOKABLE void removeFavorite(int index);
    Q_INVOKABLE void renameFavorite(int index, const QString &name);
    Q_INVOKABLE QString mgrs(double lat, double lon) const;

signals:
    void statusChanged();
    void searchChanged();
    void favoritesChanged();

private:
    void _setStatus(const QString &s, const QString &text);
    void _saveFavorites();

    QNetworkAccessManager *_net = nullptr;
    QPointer<QNetworkReply> _probeReply;
    QPointer<QNetworkReply> _searchReply;
    QElapsedTimer _probeClock;
    QString _status = QStringLiteral("idle");
    QString _statusText;
    QString _checkedType;
    int _latency = -1;
    bool _searching = false;
    QVariantList _results;
    QString _searchError;
    QVariantList _favorites;
};
