#include "MLMapService.h"

#include "MapProvider.h"
#include "QGCGeo.h"
#include "QGCMapUrlEngine.h"
#include "TerrainQuery.h"

#include <algorithm>
#include <cmath>

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QRegularExpression>
#include <QtCore/QSettings>
#include <QtCore/QUrlQuery>
#include <QtCore/QtMath>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>
#include <QtPositioning/QGeoCoordinate>

namespace {
constexpr const char *kFavGroup = "MLFavorites";
#if defined(Q_OS_WIN)
constexpr const char *kUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:100.0) Gecko/20100101 Firefox/112.0";
#else
constexpr const char *kUserAgent = "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/112.0";
#endif
}

MLMapService::MLMapService(QObject *parent)
    : QObject(parent)
    , _net(new QNetworkAccessManager(this))
{
    QSettings s;
    s.beginGroup(QLatin1String(kFavGroup));
    const QJsonArray a = QJsonDocument::fromJson(s.value(QStringLiteral("sites")).toByteArray()).array();
    for (const QJsonValue &v : a) {
        _favorites.append(v.toObject().toVariantMap());
    }
}

void MLMapService::_setStatus(const QString &s, const QString &text)
{
    _status = s;
    _statusText = text;
    emit statusChanged();
}

void MLMapService::probe(const QString &type, double lat, double lon, int zoom)
{
    if (_probeReply) {
        _probeReply->abort();
    }
    _checkedType = type;
    const auto provider = UrlFactory::getMapProviderFromProviderType(type);
    if (!provider) {
        _setStatus(QStringLiteral("error"), tr("알 수 없는 지도 유형: %1").arg(type));
        return;
    }
    zoom = qBound(3, zoom, 18);
    const int x = UrlFactory::long2tileX(type, lon, zoom);
    const int y = UrlFactory::lat2tileY(type, lat, zoom);
    const QUrl url = provider->getTileURL(x, y, zoom);
    if (!url.isValid() || url.isEmpty()) {
        _setStatus(QStringLiteral("error"), tr("이 지도 유형은 인증키가 필요합니다 (설정 › 일반에서 입력)"));
        return;
    }
    QNetworkRequest req(url);
    req.setTransferTimeout(8000);
    req.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("*/*"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QByteArray(kUserAgent));
    const QByteArray referrer = provider->getReferrer().toUtf8();
    if (!referrer.isEmpty()) {
        req.setRawHeader(QByteArrayLiteral("Referer"), referrer);
    }
    const QByteArray token = provider->getToken();
    if (!token.isEmpty()) {
        req.setRawHeader(QByteArrayLiteral("User-Token"), token);
    }
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    _setStatus(QStringLiteral("checking"), tr("지도 서버 확인 중…"));
    _probeClock.start();
    _probeReply = _net->get(req);
    QNetworkReply *r = _probeReply;
    connect(r, &QNetworkReply::finished, this, [this, r]() {
        r->deleteLater();
        if (r != _probeReply) {
            return;
        }
        _latency = static_cast<int>(_probeClock.elapsed());
        const int http = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = r->readAll();
        if (r->error() == QNetworkReply::NoError && http >= 200 && http < 300 && body.size() > 64) {
            _setStatus(QStringLiteral("ok"), tr("지도 서버 정상 · %1 ms").arg(_latency));
            return;
        }
        QString why;
        switch (r->error()) {
        case QNetworkReply::HostNotFoundError:
        case QNetworkReply::UnknownNetworkError:
        case QNetworkReply::NetworkSessionFailedError:
            why = tr("인터넷 연결 없음 (서버 주소를 찾을 수 없음) — 오프라인 지도를 쓰거나 네트워크를 확인하세요");
            break;
        case QNetworkReply::TimeoutError:
        case QNetworkReply::OperationCanceledError:
            why = tr("지도 서버 응답 없음 (8초 초과) — 다른 공급자를 선택하거나 오프라인 지도를 쓰세요");
            break;
        case QNetworkReply::ConnectionRefusedError:
        case QNetworkReply::RemoteHostClosedError:
            why = tr("지도 서버가 연결을 거부함");
            break;
        case QNetworkReply::SslHandshakeFailedError:
            why = tr("보안 연결(SSL) 실패 — PC 시간 또는 방화벽/프록시를 확인하세요");
            break;
        case QNetworkReply::ProxyConnectionRefusedError:
        case QNetworkReply::ProxyNotFoundError:
        case QNetworkReply::ProxyTimeoutError:
        case QNetworkReply::ProxyAuthenticationRequiredError:
            why = tr("프록시 연결 실패");
            break;
        default:
            if (http == 401 || http == 403) {
                why = tr("서버가 요청을 거부함 (HTTP %1) — 인증키가 없거나 이 지역/IP에서 사용할 수 없습니다").arg(http);
            } else if (http == 404) {
                why = tr("이 위치·확대 수준의 타일이 없음 (HTTP 404)");
            } else if (http == 429) {
                why = tr("요청이 너무 많음 (HTTP 429) — 잠시 후 다시 시도하세요");
            } else if (http >= 500) {
                why = tr("지도 서버 오류 (HTTP %1)").arg(http);
            } else if (http >= 200 && http < 300) {
                why = tr("서버가 빈 타일을 보냄 — 인증키 또는 지역 제한을 확인하세요");
            } else {
                why = tr("지도 요청 실패: %1").arg(r->errorString());
            }
        }
        _setStatus(QStringLiteral("error"), why);
    });
}

QVariantMap MLMapService::parseCoordinate(const QString &textIn) const
{
    QString text = textIn.trimmed();
    if (text.isEmpty()) {
        return {{QStringLiteral("ok"), false}};
    }
    // decimal degrees "37.21, 126.83" / "37.21 126.83"
    static const QRegularExpression dec(QStringLiteral("^\\s*([-+]?\\d{1,2}(?:\\.\\d+)?)\\s*[, ]\\s*([-+]?\\d{1,3}(?:\\.\\d+)?)\\s*$"));
    auto m = dec.match(text);
    if (m.hasMatch()) {
        const double lat = m.captured(1).toDouble(), lon = m.captured(2).toDouble();
        if (qAbs(lat) <= 90 && qAbs(lon) <= 180) {
            return {{QStringLiteral("ok"), true}, {QStringLiteral("lat"), lat}, {QStringLiteral("lon"), lon}, {QStringLiteral("kind"), QStringLiteral("dec")}};
        }
    }
    // DMS "37°12'36.1\"N 126°49'51.0\"E" (also 37 12 36.1 N 126 49 51 E)
    static const QRegularExpression dms(QStringLiteral(
        "^\\s*(\\d{1,2})[°\\s]+(\\d{1,2})['′\\s]+(\\d{1,2}(?:\\.\\d+)?)[\"″\\s]*([NSns])[\\s,]+(\\d{1,3})[°\\s]+(\\d{1,2})['′\\s]+(\\d{1,2}(?:\\.\\d+)?)[\"″\\s]*([EWew])\\s*$"));
    m = dms.match(text);
    if (m.hasMatch()) {
        double lat = m.captured(1).toDouble() + m.captured(2).toDouble() / 60 + m.captured(3).toDouble() / 3600;
        double lon = m.captured(5).toDouble() + m.captured(6).toDouble() / 60 + m.captured(7).toDouble() / 3600;
        if (m.captured(4).toUpper() == QLatin1String("S")) lat = -lat;
        if (m.captured(8).toUpper() == QLatin1String("W")) lon = -lon;
        return {{QStringLiteral("ok"), true}, {QStringLiteral("lat"), lat}, {QStringLiteral("lon"), lon}, {QStringLiteral("kind"), QStringLiteral("dms")}};
    }
    // MGRS
    static const QRegularExpression mg(QStringLiteral("^\\s*\\d{1,2}[C-HJ-NP-Xc-hj-np-x]\\s*[A-HJ-NP-Za-hj-np-z]{2}\\s*\\d{1,5}\\s*\\d{1,5}\\s*$"));
    if (mg.match(text).hasMatch()) {
        QGeoCoordinate c;
        if (QGCGeo::convertMGRSToGeo(text.toUpper(), c) && c.isValid()) {
            return {{QStringLiteral("ok"), true}, {QStringLiteral("lat"), c.latitude()}, {QStringLiteral("lon"), c.longitude()}, {QStringLiteral("kind"), QStringLiteral("mgrs")}};
        }
    }
    return {{QStringLiteral("ok"), false}};
}

void MLMapService::search(const QString &text, double nearLat, double nearLon)
{
    if (_searchReply) {
        _searchReply->abort();
    }
    _results.clear();
    _searchError.clear();
    const QVariantMap c = parseCoordinate(text);
    if (c.value(QStringLiteral("ok")).toBool()) {
        QVariantMap r = c;
        r[QStringLiteral("name")] = tr("좌표 %1, %2").arg(c[QStringLiteral("lat")].toDouble(), 0, 'f', 6).arg(c[QStringLiteral("lon")].toDouble(), 0, 'f', 6);
        r[QStringLiteral("detail")] = c[QStringLiteral("kind")].toString().toUpper();
        _results.append(r);
        _searching = false;
        emit searchChanged();
        return;
    }
    if (text.trimmed().size() < 2) {
        _searching = false;
        emit searchChanged();
        return;
    }
    QUrl url(QStringLiteral("https://nominatim.openstreetmap.org/search"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("q"), text.trimmed());
    q.addQueryItem(QStringLiteral("format"), QStringLiteral("jsonv2"));
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("8"));
    q.addQueryItem(QStringLiteral("accept-language"), QStringLiteral("ko,en"));
    if (!qIsNaN(nearLat) && !qIsNaN(nearLon)) {
        // prefer results near the map centre (±1.5°), still allow others
        q.addQueryItem(QStringLiteral("viewbox"), QStringLiteral("%1,%2,%3,%4").arg(nearLon - 1.5).arg(nearLat + 1.5).arg(nearLon + 1.5).arg(nearLat - 1.5));
    }
    url.setQuery(q);
    QNetworkRequest req(url);
    req.setTransferTimeout(10000);
    req.setHeader(QNetworkRequest::UserAgentHeader, QByteArrayLiteral("MobilityLabGCS/1.0 (ground control station; contact via github.com/4424904/MobilityLabGCS)"));
    _searching = true;
    emit searchChanged();
    _searchReply = _net->get(req);
    QNetworkReply *r = _searchReply;
    connect(r, &QNetworkReply::finished, this, [this, r]() {
        r->deleteLater();
        if (r != _searchReply) {
            return;
        }
        _searching = false;
        if (r->error() != QNetworkReply::NoError) {
            _searchError = r->error() == QNetworkReply::HostNotFoundError || r->error() == QNetworkReply::UnknownNetworkError
                               ? tr("인터넷 연결 없음 — 좌표(위도, 경도 · MGRS)로 검색하거나 즐겨찾기를 쓰세요")
                               : tr("장소 검색 실패: %1").arg(r->errorString());
            emit searchChanged();
            return;
        }
        const QJsonArray a = QJsonDocument::fromJson(r->readAll()).array();
        for (const QJsonValue &v : a) {
            const QJsonObject o = v.toObject();
            QString name = o.value(QStringLiteral("name")).toString();
            const QString disp = o.value(QStringLiteral("display_name")).toString();
            if (name.isEmpty()) {
                name = disp.section(QLatin1Char(','), 0, 0);
            }
            _results.append(QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("detail"), disp},
                                        {QStringLiteral("lat"), o.value(QStringLiteral("lat")).toString().toDouble()},
                                        {QStringLiteral("lon"), o.value(QStringLiteral("lon")).toString().toDouble()},
                                        {QStringLiteral("kind"), QStringLiteral("place")}});
        }
        if (_results.isEmpty()) {
            _searchError = tr("검색 결과 없음");
        }
        emit searchChanged();
    });
}

void MLMapService::clearSearch()
{
    if (_searchReply) {
        _searchReply->abort();
    }
    _results.clear();
    _searchError.clear();
    _searching = false;
    emit searchChanged();
}

void MLMapService::_saveFavorites()
{
    QJsonArray a;
    for (const QVariant &v : std::as_const(_favorites)) {
        a.append(QJsonObject::fromVariantMap(v.toMap()));
    }
    QSettings s;
    s.beginGroup(QLatin1String(kFavGroup));
    s.setValue(QStringLiteral("sites"), QJsonDocument(a).toJson(QJsonDocument::Compact));
    emit favoritesChanged();
}

void MLMapService::addFavorite(const QString &name, double lat, double lon, double zoom, const QString &note)
{
    _favorites.append(QVariantMap{{QStringLiteral("name"), name.trimmed().isEmpty() ? tr("시험장 %1").arg(_favorites.size() + 1) : name.trimmed()},
                                  {QStringLiteral("lat"), lat}, {QStringLiteral("lon"), lon}, {QStringLiteral("zoom"), zoom},
                                  {QStringLiteral("note"), note}});
    _saveFavorites();
}

void MLMapService::removeFavorite(int index)
{
    if (index >= 0 && index < _favorites.size()) {
        _favorites.removeAt(index);
        _saveFavorites();
    }
}

void MLMapService::renameFavorite(int index, const QString &name)
{
    if (index >= 0 && index < _favorites.size() && !name.trimmed().isEmpty()) {
        QVariantMap m = _favorites[index].toMap();
        m[QStringLiteral("name")] = name.trimmed();
        _favorites[index] = m;
        _saveFavorites();
    }
}

QString MLMapService::mgrs(double lat, double lon) const
{
    return QGCGeo::convertGeoToMGRS(QGeoCoordinate(lat, lon));
}

void MLMapService::requestTerrainGrid(double lat, double lon, double sizeM, int n)
{
    n = std::clamp(n, 2, 65);
    QList<QGeoCoordinate> coords;
    const double kx = std::cos(qDegreesToRadians(lat)) * 111320.0, ky = 110574.0;
    for (int j = 0; j < n; j++) {          // north → south rows
        for (int i = 0; i < n; i++) {      // west → east
            const double e = -sizeM / 2 + sizeM * i / (n - 1), nn = sizeM / 2 - sizeM * j / (n - 1);
            coords.append(QGeoCoordinate(lat + nn / ky, lon + e / kx));
        }
    }
    auto done = [this, lat, lon, sizeM, n](bool ok, const QList<double> &h) {
        QVariantList out;
        if (ok && h.size() == n * n) {
            for (double v : h) out << v;
        }
        emit terrainGrid(ok && !out.isEmpty(), out, lat, lon, sizeM, n);
    };
    QList<double> cached;
    bool err = false;
    if (TerrainAtCoordinateQuery::getAltitudesForCoordinates(coords, cached, err)) {
        done(!err, cached);
        return;
    }
    auto *q = new TerrainAtCoordinateQuery(true);
    connect(q, &TerrainAtCoordinateQuery::terrainDataReceived, this, done);
    q->requestData(coords);
}
