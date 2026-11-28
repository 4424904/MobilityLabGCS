#include "MLFlightRecords.h"

#include "MLAcactRuntime.h"
#include "MLDemo.h"

#include "Fact.h"
#include "FactGroup.h"
#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "TerrainQuery.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QLoggingCategory>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtPositioning/QGeoCoordinate>
#include <QtCore/QtMath>
#include <QtGui/QFont>
#include <QtGui/QPageLayout>
#include <QtGui/QPageSize>
#include <QtGui/QPainter>
#include <QtGui/QPainterPath>
#include <QtGui/QPdfWriter>
#include <QtSvg/QSvgRenderer>

#include <algorithm>
#include <cmath>
#include <limits>

#ifndef ML_GCS_VERSION
#define ML_GCS_VERSION "dev"
#endif

Q_LOGGING_CATEGORY(MLRecordsLog, "MobilityLab.Records")

namespace {
constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();
double factVal(FactGroup *g, const char *name)
{
    if (!g) {
        return kNaN;
    }
    Fact *f = g->getFact(QString::fromLatin1(name));
    if (!f) {
        return kNaN;
    }
    bool ok = false;
    const double v = f->rawValue().toDouble(&ok);
    return ok ? v : kNaN;
}
QString num(double v, int d)
{
    return std::isnan(v) ? QString() : QString::number(v, 'f', d);
}
double haversine(double lat1, double lon1, double lat2, double lon2)
{
    const double R = 6371000.0, p1 = qDegreesToRadians(lat1), p2 = qDegreesToRadians(lat2);
    const double dp = p2 - p1, dl = qDegreesToRadians(lon2 - lon1);
    const double a = std::sin(dp / 2) * std::sin(dp / 2) + std::cos(p1) * std::cos(p2) * std::sin(dl / 2) * std::sin(dl / 2);
    return 2 * R * std::asin(std::min(1.0, std::sqrt(a)));
}
const char *kHeader = "t,sysid,lat,lon,alt_rel,alt_amsl,agl,gs,vs,hdg,roll,pitch,batt_pct,batt_v,gps_fix,sats,hdop,link_lost,armed,acact_own,mode";
} // namespace

MLFlightRecords::MLFlightRecords(QObject *parent)
    : QObject(parent)
{
    _timer.setInterval(500);
    connect(&_timer, &QTimer::timeout, this, &MLFlightRecords::_tick);
    _timer.start();
    _clock.start();
}

void MLFlightRecords::attach(MLAcactRuntime *guard, MLDemo *demo)
{
    _guard = guard;
    _demo = demo;
}

QString MLFlightRecords::baseDir() const
{
    const QString custom = QSettings().value(QStringLiteral("MLRecords/baseDir")).toString();
    if (!custom.isEmpty()) {
        return custom;
    }
    if (qEnvironmentVariableIsSet("MLGCS_PORTABLE_DIR")) {
        return QDir(qEnvironmentVariable("MLGCS_PORTABLE_DIR")).filePath(QStringLiteral("data/Records"));
    }
    return QDir(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)).filePath(QStringLiteral("MobilityLab/Records"));
}

void MLFlightRecords::setBaseDir(const QString &dir)
{
    if (_rec) {
        return;     // never move the folder under a running record
    }
    QString d = dir;
    if (d.startsWith(QLatin1String("file://"))) {
        d = QUrl(d).toLocalFile();
    }
    QSettings().setValue(QStringLiteral("MLRecords/baseDir"), d);
    emit baseDirChanged();
    refresh();
}

QString MLFlightRecords::recordDir(const QString &stamp) const
{
    for (const QString sub : {QStringLiteral("Flights"), QStringLiteral("Demo")}) {
        const QString d = QDir(baseDir()).filePath(sub + QLatin1Char('/') + stamp);
        if (QFileInfo::exists(d)) {
            return d;
        }
    }
    return QString();
}

// "demo" while the built-in demo runs; otherwise the operating mode declared for the guard
// ("sim" SITL / "field" real aircraft); "field" when nothing is declared
QString MLFlightRecords::_kindNow() const
{
    if (_demo && _demo->active()) {
        return QStringLiteral("demo");
    }
    if (_guard && _guard->opMode() == QLatin1String("sim")) {
        return QStringLiteral("sim");
    }
    return QStringLiteral("field");
}

QVariantMap MLFlightRecords::_vehicleInfo() const
{
    QVariantMap out;
    QmlObjectListModel *vs = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vs->count(); i++) {
        Vehicle *v = qobject_cast<Vehicle *>(vs->get(i));
        if (!v) {
            continue;
        }
        QVariantMap m;
        m[QStringLiteral("sysid")] = v->id();
        m[QStringLiteral("type")] = v->vehicleTypeString();
        m[QStringLiteral("firmware")] = v->firmwareTypeString();
        m[QStringLiteral("fwVersion")] = QStringLiteral("%1.%2.%3").arg(v->firmwareMajorVersion()).arg(v->firmwareMinorVersion()).arg(v->firmwarePatchVersion());
        out[QString::number(v->id())] = m;
    }
    return out;
}

// ---- terrain height under each vehicle (QGC terrain database) ---------------------------------------
// AGL = vehicle AMSL − terrain height. Unlike QGC's altitudeAboveTerr fact (0 until the first answer,
// then the last value even if later queries fail) this keeps track of whether the height is known and
// fresh: no answer → no AGL ("미기록" / "—"), never 0.
void MLFlightRecords::_terrainTick()
{
    QmlObjectListModel *vs = MultiVehicleManager::instance()->vehicles();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (int i = 0; i < vs->count(); i++) {
        Vehicle *v = qobject_cast<Vehicle *>(vs->get(i));
        if (!v) continue;
        const QGeoCoordinate c = v->coordinate();
        if (!c.isValid()) continue;
        Terr &tr = _terr[v->id()];
        if (tr.pending || now - tr.askMs < 1000) continue;
        const bool need = tr.okMs == 0 ? now - tr.askMs > 5000
                                       : (tr.at.distanceTo(c) > 15.0 || now - tr.okMs > 10000);
        if (!need) continue;
        tr.askMs = now;
        const int id = v->id();
        auto apply = [this, id, c](bool ok, const QList<double> &h) {
            Terr &t = _terr[id];
            t.pending = false;
            if (ok && !h.isEmpty() && !std::isnan(h.first())) {
                t.h = h.first();
                t.at = c;
                t.okMs = QDateTime::currentMSecsSinceEpoch();
            }
        };
        QList<double> cached;
        bool err = false;
        if (TerrainAtCoordinateQuery::getAltitudesForCoordinates({c}, cached, err)) {
            apply(!err, cached);
            continue;
        }
        tr.pending = true;
        auto *q = new TerrainAtCoordinateQuery(true /* autoDelete */);
        connect(q, &TerrainAtCoordinateQuery::terrainDataReceived, this, apply);
        q->requestData({c});
    }
    emit aglChanged();
}

double MLFlightRecords::_aglOf(int sysid, double amsl, const QGeoCoordinate &pos) const
{
    const auto it = _terr.constFind(sysid);
    if (it == _terr.constEnd() || it->okMs == 0 || std::isnan(amsl) || std::isnan(it->h)) return kNaN;
    if (!pos.isValid() || it->at.distanceTo(pos) > 50.0) return kNaN;          // height of another place
    if (QDateTime::currentMSecsSinceEpoch() - it->okMs > 30000) return kNaN;
    return amsl - it->h;
}

QVariantMap MLFlightRecords::agl() const
{
    QVariantMap out;
    QmlObjectListModel *vs = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vs->count(); i++) {
        Vehicle *v = qobject_cast<Vehicle *>(vs->get(i));
        if (!v) continue;
        const auto it = _terr.constFind(v->id());
        const double a = _aglOf(v->id(), factVal(v, "altitudeAMSL"), v->coordinate());
        if (std::isnan(a)) continue;
        out[QString::number(v->id())] = QVariantMap{{QStringLiteral("agl"), a}, {QStringLiteral("terrain"), it->h},
                                                    {QStringLiteral("age"), (QDateTime::currentMSecsSinceEpoch() - it->okMs) / 1000.0}};
    }
    return out;
}

void MLFlightRecords::_tick()
{
    _terrainTick();
    QmlObjectListModel *vs = MultiVehicleManager::instance()->vehicles();
    const double now = _clock.elapsed() / 1000.0;
    bool anyArmed = false;
    for (int i = 0; i < vs->count(); i++) {
        Vehicle *v = qobject_cast<Vehicle *>(vs->get(i));
        if (v && v->armed()) {
            anyArmed = true;
        }
    }
    if (anyArmed) {
        _lastArmed = now;
    }
    if (!_rec && anyArmed) {
        _start();
    }
    if (!_rec) {
        return;
    }
    // demo and real never mix: a change of kind (demo started / stopped) closes the record
    if (_kindNow() != _curKind || vs->count() == 0 || (!anyArmed && now - _lastArmed > 20.0)) {
        _stop();
        return;
    }

    // keep the vehicle list in meta up to date (vehicles that connect during the flight)
    const QVariantMap vi = _vehicleInfo();
    bool newVeh = false;
    for (auto it = vi.begin(); it != vi.end(); ++it) {
        if (!_curVeh.contains(it.key())) {
            _curVeh[it.key()] = it.value();
            newVeh = true;
        }
    }
    if (newVeh) {
        QVariantMap m = _readMeta(_curDir);
        m[QStringLiteral("vehicles")] = _curVeh;
        _writeMeta(_curDir, m);
    }

    QHash<int, bool> own;
    if (_guard && _guard->running()) {
        for (const QVariant &dv : _guard->drones()) {
            const QVariantMap d = dv.toMap();
            own[d.value(QStringLiteral("sysid")).toInt()] = d.value(QStringLiteral("phase")).toString() == QLatin1String("avoid");
        }
    }
    const double t = (QDateTime::currentMSecsSinceEpoch() - QDateTime::fromString(_curStamp, QStringLiteral("yyyyMMdd_HHmmss")).toMSecsSinceEpoch()) / 1000.0;
    QTextStream ts(&_track);
    for (int i = 0; i < vs->count(); i++) {
        Vehicle *v = qobject_cast<Vehicle *>(vs->get(i));
        if (!v) {
            continue;
        }
        const QGeoCoordinate c = v->coordinate();
        FactGroup *gps = v->getFactGroup(QStringLiteral("gps"));
        double pct = kNaN, volt = kNaN;
        if (v->batteries()->count() > 0) {
            FactGroup *b = qobject_cast<FactGroup *>(v->batteries()->get(0));
            pct = factVal(b, "percentRemaining");
            volt = factVal(b, "voltage");
        }
        const double fix = factVal(gps, "lock"), sats = factVal(gps, "count");
        ts << QString::number(t, 'f', 2) << ',' << v->id() << ','
           << (c.isValid() ? QString::number(c.latitude(), 'f', 7) : QString()) << ','
           << (c.isValid() ? QString::number(c.longitude(), 'f', 7) : QString()) << ','
           << num(factVal(v, "altitudeRelative"), 2) << ',' << num(factVal(v, "altitudeAMSL"), 2) << ','
           << num(_aglOf(v->id(), factVal(v, "altitudeAMSL"), c), 2) << ',' << num(factVal(v, "groundSpeed"), 2) << ','
           << num(factVal(v, "climbRate"), 2) << ',' << num(factVal(v, "heading"), 1) << ','
           << num(factVal(v, "roll"), 1) << ',' << num(factVal(v, "pitch"), 1) << ','
           << num(pct, 0) << ',' << num(volt, 2) << ','
           << (std::isnan(fix) ? QString() : QString::number(int(fix))) << ',' << (std::isnan(sats) ? QString() : QString::number(int(sats))) << ','
           << num(factVal(gps, "hdop"), 2) << ','
           << (v->vehicleLinkManager()->communicationLost() ? 1 : 0) << ',' << (v->armed() ? 1 : 0) << ','
           << (own.value(v->id(), false) ? 1 : 0) << ',' << QString(v->flightMode()).replace(QLatin1Char(','), QLatin1Char(' ')) << '\n';
    }
    ts.flush();
    // link the guard log of this flight (written by MLAcactRuntime) once it exists
    if (_guard && _guard->running()) {
        const QString g = QFileInfo(_guard->lastLogFile()).completeBaseName().remove(QStringLiteral("guard_"));
        QVariantMap m = _readMeta(_curDir);
        QStringList gl = m.value(QStringLiteral("guardLogs")).toStringList();
        if (!g.isEmpty() && !gl.contains(g)) {
            gl << g;
            m[QStringLiteral("guardLogs")] = gl;
            _writeMeta(_curDir, m);
        }
    }
}

void MLFlightRecords::_start()
{
    _curKind = _kindNow();
    _curStamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
    _curDir = QDir(baseDir()).filePath((_curKind == QLatin1String("demo") ? QStringLiteral("Demo/") : QStringLiteral("Flights/")) + _curStamp);
    if (!QDir().mkpath(_curDir)) {
        qCWarning(MLRecordsLog) << "cannot create" << _curDir;
        return;
    }
    _track.setFileName(QDir(_curDir).filePath(QStringLiteral("track.csv")));
    _events.setFileName(QDir(_curDir).filePath(QStringLiteral("events.csv")));
    if (!_track.open(QIODevice::WriteOnly | QIODevice::Text) || !_events.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qCWarning(MLRecordsLog) << "cannot open record files in" << _curDir;
        return;
    }
    _track.write(kHeader);
    _track.write("\n");
    _events.write("t,time,level,source,sysid,text\n");
    _curVeh = _vehicleInfo();
    QVariantMap m;
    m[QStringLiteral("stamp")] = _curStamp;
    m[QStringLiteral("kind")] = _curKind;
    m[QStringLiteral("gcsVersion")] = QStringLiteral(ML_GCS_VERSION);
    m[QStringLiteral("started")] = QDateTime::currentDateTime().toString(Qt::ISODate);
    m[QStringLiteral("vehicles")] = _curVeh;
    if (_guard) {
        QVariantList missions;
        const QVariantList mv = _guard->missionCheck().value(QStringLiteral("vehicles")).toList();
        for (const QVariant &x : mv) {
            const QVariantMap mm = x.toMap();
            QVariantMap s;
            s[QStringLiteral("sysid")] = mm.value(QStringLiteral("sysid"));
            s[QStringLiteral("navItems")] = mm.value(QStringLiteral("navItems"));
            s[QStringLiteral("length")] = mm.value(QStringLiteral("length"));
            s[QStringLiteral("maxAlt")] = mm.value(QStringLiteral("maxAlt"));
            s[QStringLiteral("path")] = mm.value(QStringLiteral("path"));
            missions << s;
        }
        m[QStringLiteral("missions")] = missions;
    }
    _writeMeta(_curDir, m);
    _rec = true;
    qCWarning(MLRecordsLog).noquote() << "MLREC start" << _curKind << _curStamp;
    emit recordingChanged();
}

void MLFlightRecords::_stop()
{
    if (!_rec) {
        return;
    }
    QVariantMap m = _readMeta(_curDir);
    m[QStringLiteral("ended")] = QDateTime::currentDateTime().toString(Qt::ISODate);
    _writeMeta(_curDir, m);
    _track.close();
    _events.close();
    _rec = false;
    qCWarning(MLRecordsLog).noquote() << "MLREC stop" << _curKind << _curStamp;
    emit recordingChanged();
    refresh();
    if (qEnvironmentVariableIsSet("MLGCS_REC_SELFTEST")) {
        // CI only: open the record that just closed and export it, so the check sees real files
        const QString st = _curStamp;
        if (load(st)) {
            const QVariantMap sm = summary();
            qCWarning(MLRecordsLog).noquote() << "MLREC loaded" << st << "duration" << duration()
                                              << "vehicles" << vehicles().size() << "events" << events().size();
            const QString pdf = exportPdf(QDir(recordDir(st)).filePath(QStringLiteral("report.pdf")));
            const QString csv = exportCsv(QDir(recordDir(st)).filePath(QStringLiteral("summary.csv")));
            qCWarning(MLRecordsLog).noquote() << "MLREC export pdf" << (pdf.isEmpty() ? QStringLiteral("FAIL") : pdf)
                                              << "csv" << (csv.isEmpty() ? QStringLiteral("FAIL") : csv);
            Q_UNUSED(sm)
        } else {
            qCWarning(MLRecordsLog).noquote() << "MLREC loaded FAIL" << st;
        }
    }
}

void MLFlightRecords::event(int level, const QString &source, const QString &text, int sysid)
{
    if (!_rec || !_events.isOpen()) {
        return;
    }
    const double t = (QDateTime::currentMSecsSinceEpoch() - QDateTime::fromString(_curStamp, QStringLiteral("yyyyMMdd_HHmmss")).toMSecsSinceEpoch()) / 1000.0;
    QString tx = text;
    tx.replace(QLatin1Char('\n'), QLatin1Char(' ')).replace(QLatin1Char('"'), QLatin1Char('\''));
    QTextStream ts(&_events);
    ts << QString::number(t, 'f', 1) << ',' << QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")) << ',' << level << ','
       << QString(source).remove(QLatin1Char(',')) << ',' << sysid << ",\"" << tx << "\"\n";
    ts.flush();
}

void MLFlightRecords::_writeMeta(const QString &dir, const QVariantMap &m) const
{
    QFile f(QDir(dir).filePath(QStringLiteral("meta.json")));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(QJsonObject::fromVariantMap(m)).toJson(QJsonDocument::Indented));
    }
}

QVariantMap MLFlightRecords::_readMeta(const QString &dir) const
{
    QFile f(QDir(dir).filePath(QStringLiteral("meta.json")));
    if (!f.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
}

void MLFlightRecords::refresh(const QString &kind, const QString &text)
{
    _records.clear();
    QStringList subs;
    if (kind == QLatin1String("demo")) {
        subs << QStringLiteral("Demo");
    } else if (kind == QLatin1String("all")) {
        subs << QStringLiteral("Flights") << QStringLiteral("Demo");
    } else {
        subs << QStringLiteral("Flights");
    }
    QList<QVariantMap> all;
    for (const QString &sub : subs) {
        QDir d(QDir(baseDir()).filePath(sub));
        for (const QString &s : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed)) {
            QVariantMap m = _readMeta(d.filePath(s));
            if (m.isEmpty()) {
                continue;
            }
            QStringList vs;
            const QVariantMap vm = m.value(QStringLiteral("vehicles")).toMap();
            for (auto it = vm.begin(); it != vm.end(); ++it) {
                const QVariantMap v = it.value().toMap();
                vs << QStringLiteral("UAV %1 %2").arg(v.value(QStringLiteral("sysid")).toInt(), 2, 10, QLatin1Char('0')).arg(v.value(QStringLiteral("type")).toString());
            }
            m[QStringLiteral("vehicleText")] = vs.join(QStringLiteral(" · "));
            m[QStringLiteral("recording")] = _rec && s == _curStamp;
            if (!text.isEmpty()) {
                const QString hay = QStringList{m.value(QStringLiteral("title")).toString(), m.value(QStringLiteral("purpose")).toString(),
                                                m.value(QStringLiteral("site")).toString(), m.value(QStringLiteral("operator")).toString(),
                                                m.value(QStringLiteral("notes")).toString(), vs.join(QLatin1Char(' ')), s}.join(QLatin1Char(' '));
                if (!hay.contains(text, Qt::CaseInsensitive)) {
                    continue;
                }
            }
            all << m;
        }
    }
    std::sort(all.begin(), all.end(), [](const QVariantMap &a, const QVariantMap &b) { return a.value(QStringLiteral("stamp")).toString() > b.value(QStringLiteral("stamp")).toString(); });
    for (const QVariantMap &m : all) {
        _records << m;
    }
    emit recordsChanged();
}

bool MLFlightRecords::setUserFields(const QString &stamp, const QVariantMap &fields)
{
    const QString dir = recordDir(stamp);
    if (dir.isEmpty()) {
        return false;
    }
    QVariantMap m = _readMeta(dir);
    static const QStringList allowed{QStringLiteral("title"), QStringLiteral("purpose"), QStringLiteral("site"), QStringLiteral("operator"),
                                     QStringLiteral("notes"), QStringLiteral("judgement"), QStringLiteral("judgementNote"), QStringLiteral("method"),
                                     QStringLiteral("conditions")};
    for (auto it = fields.begin(); it != fields.end(); ++it) {
        if (allowed.contains(it.key())) {
            m[it.key()] = it.value().toString();
        }
    }
    _writeMeta(dir, m);
    if (stamp == _stamp) {
        _meta = m;
        emit loadedChanged();
    }
    refresh(m.value(QStringLiteral("kind")).toString() == QLatin1String("demo") ? QStringLiteral("demo") : QString());
    return true;
}

void MLFlightRecords::unload()
{
    _stamp.clear();
    _veh.clear();
    _vehV.clear();
    _pairV.clear();
    _evV.clear();
    _summary.clear();
    _meta.clear();
    emit loadedChanged();
}

bool MLFlightRecords::load(const QString &stamp)
{
    const QString dir = recordDir(stamp);
    if (dir.isEmpty()) {
        return false;
    }
    QFile f(QDir(dir).filePath(QStringLiteral("track.csv")));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }
    _veh.clear();
    QHash<int, int> idx;
    QTextStream ts(&f);
    ts.readLine();
    auto fv = [](const QString &s) { bool ok = false; const float v = s.toFloat(&ok); return ok ? v : std::numeric_limits<float>::quiet_NaN(); };
    while (!ts.atEnd()) {
        const QStringList c = ts.readLine().split(QLatin1Char(','));
        if (c.size() < 21) {
            continue;
        }
        const int sysid = c[1].toInt();
        if (!idx.contains(sysid)) {
            idx[sysid] = _veh.size();
            Veh v;
            v.sysid = sysid;
            _veh << v;
        }
        Row r;
        r.t = fv(c[0]); r.lat = fv(c[2]); r.lon = fv(c[3]); r.alt = fv(c[4]); r.amsl = fv(c[5]); r.agl = fv(c[6]);
        r.gs = fv(c[7]); r.vs = fv(c[8]); r.hdg = fv(c[9]); r.roll = fv(c[10]); r.pitch = fv(c[11]);
        r.pct = fv(c[12]); r.volt = fv(c[13]);
        r.fix = c[14].isEmpty() ? -1 : static_cast<qint8>(c[14].toInt());
        r.sats = c[15].isEmpty() ? -1 : static_cast<qint8>(c[15].toInt());
        r.hdop = fv(c[16]);
        r.lost = static_cast<quint8>(c[17].toInt()); r.armed = static_cast<quint8>(c[18].toInt()); r.own = static_cast<quint8>(c[19].toInt());
        r.mode = c[20];
        _veh[idx[sysid]].rows << r;
    }
    _evV.clear();
    QFile ef(QDir(dir).filePath(QStringLiteral("events.csv")));
    if (ef.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream es(&ef);
        es.readLine();
        while (!es.atEnd()) {
            const QString line = es.readLine();
            const QStringList c = line.split(QLatin1Char(','));
            if (c.size() < 6) {
                continue;
            }
            QVariantMap e;
            e[QStringLiteral("t")] = c[0].toDouble();
            e[QStringLiteral("time")] = c[1];
            e[QStringLiteral("level")] = c[2].toInt();
            e[QStringLiteral("source")] = c[3];
            e[QStringLiteral("sysid")] = c[4].toInt();
            QString text = line.section(QLatin1Char(','), 5);
            if (text.startsWith(QLatin1Char('"')) && text.endsWith(QLatin1Char('"'))) {
                text = text.mid(1, text.size() - 2);
            }
            e[QStringLiteral("text")] = text;
            _evV << e;
        }
    }
    _stamp = stamp;
    _dir = dir;
    _meta = _readMeta(dir);
    _compute();
    emit loadedChanged();
    return true;
}

// Metrics from the recorded samples only. A value that was never received stays "미기록".
void MLFlightRecords::_compute()
{
    _vehV.clear();
    _pairV.clear();
    _summary.clear();
    _extent.clear();
    double tMax = 0;
    double latMin = 90, latMax = -90, lonMin = 180, lonMax = -180, altMax = 0;
    int interventions = 0;
    double ownTime = 0;
    for (const Veh &v : std::as_const(_veh)) {
        double dist = 0, maxAlt = kNaN, maxGs = kNaN, sumGs = 0, armedT = 0, lostT = 0, avoidT = 0;
        int nGs = 0, lostN = 0, avoidN = 0, minSats = -1;
        double maxHdop = kNaN, pct0 = kNaN, pct1 = kNaN, vMin = kNaN, v0 = kNaN, v1 = kNaN, fixBadT = 0;
        QVariantList modes, series;
        QString lastMode;
        for (int i = 0; i < v.rows.size(); i++) {
            const Row &r = v.rows[i];
            const double dt = i > 0 ? std::max(0.0, double(r.t - v.rows[i - 1].t)) : 0.0;
            tMax = std::max(tMax, double(r.t));
            if (!std::isnan(r.lat)) {
                latMin = std::min(latMin, double(r.lat)); latMax = std::max(latMax, double(r.lat));
                lonMin = std::min(lonMin, double(r.lon)); lonMax = std::max(lonMax, double(r.lon));
            }
            if (i > 0 && r.armed && !std::isnan(r.lat) && !std::isnan(v.rows[i - 1].lat)) {
                const double d = haversine(v.rows[i - 1].lat, v.rows[i - 1].lon, r.lat, r.lon);
                if (d < 60.0) {   // a jump of more than 60 m in 0.5 s is a position reset, not flight
                    dist += d;
                }
            }
            if (r.armed) {
                armedT += dt;
                if (!std::isnan(r.alt)) { maxAlt = std::isnan(maxAlt) ? r.alt : std::max(maxAlt, double(r.alt)); }
                if (!std::isnan(r.gs)) { maxGs = std::isnan(maxGs) ? r.gs : std::max(maxGs, double(r.gs)); sumGs += r.gs; nGs++; }
            }
            if (!std::isnan(r.alt)) {
                altMax = std::max(altMax, double(r.alt));
            }
            if (r.lost) {
                lostT += dt;
                if (i == 0 || !v.rows[i - 1].lost) lostN++;
            }
            if (r.own) {
                avoidT += dt;
                if (i == 0 || !v.rows[i - 1].own) avoidN++;
            }
            if (r.sats >= 0) minSats = minSats < 0 ? r.sats : std::min<int>(minSats, r.sats);
            if (!std::isnan(r.hdop)) maxHdop = std::isnan(maxHdop) ? r.hdop : std::max(maxHdop, double(r.hdop));
            if (r.fix >= 0 && r.fix < 3 && r.armed) fixBadT += dt;
            if (!std::isnan(r.pct)) { if (std::isnan(pct0)) pct0 = r.pct; pct1 = r.pct; }
            if (!std::isnan(r.volt) && r.volt > 0.1) { if (std::isnan(v0)) v0 = r.volt; v1 = r.volt; vMin = std::isnan(vMin) ? r.volt : std::min(vMin, double(r.volt)); }
            if (r.mode != lastMode) {
                modes << QVariantMap{{QStringLiteral("t"), r.t}, {QStringLiteral("mode"), r.mode}};
                lastMode = r.mode;
            }
            if (i % 2 == 0) {   // 1 Hz series for charts
                // one row = one element (QList << QList would append the row's items one by one)
                series << QVariant(QVariantList{r.t, std::isnan(r.alt) ? QVariant() : QVariant(r.alt), std::isnan(r.gs) ? QVariant() : QVariant(r.gs),
                                       std::isnan(r.pct) ? QVariant() : QVariant(r.pct), std::isnan(r.volt) ? QVariant() : QVariant(r.volt), int(r.lost), int(r.own)});
            }
        }
        interventions += avoidN;
        ownTime += avoidT;
        auto val = [](double x) { return std::isnan(x) ? QVariant() : QVariant(x); };
        QVariantMap m;
        m[QStringLiteral("sysid")] = v.sysid;
        m[QStringLiteral("samples")] = v.rows.size();
        m[QStringLiteral("armedTime")] = armedT;
        m[QStringLiteral("distance")] = dist;
        m[QStringLiteral("maxAlt")] = val(maxAlt);
        m[QStringLiteral("maxSpeed")] = val(maxGs);
        m[QStringLiteral("meanSpeed")] = nGs ? QVariant(sumGs / nGs) : QVariant();
        m[QStringLiteral("battStart")] = val(pct0);
        m[QStringLiteral("battEnd")] = val(pct1);
        m[QStringLiteral("voltStart")] = val(v0);
        m[QStringLiteral("voltEnd")] = val(v1);
        m[QStringLiteral("voltMin")] = val(vMin);
        m[QStringLiteral("minSats")] = minSats < 0 ? QVariant() : QVariant(minSats);
        m[QStringLiteral("maxHdop")] = val(maxHdop);
        m[QStringLiteral("noFixTime")] = fixBadT;
        m[QStringLiteral("linkLost")] = lostN;
        m[QStringLiteral("linkLostTime")] = lostT;
        m[QStringLiteral("acactInterventions")] = avoidN;
        m[QStringLiteral("acactTime")] = avoidT;
        m[QStringLiteral("modes")] = modes;
        m[QStringLiteral("series")] = series;
        m[QStringLiteral("info")] = _meta.value(QStringLiteral("vehicles")).toMap().value(QString::number(v.sysid));
        _vehV << m;
    }
    // separation between every pair from positions recorded in the same tick
    for (int a = 0; a < _veh.size(); a++) {
        for (int b = a + 1; b < _veh.size(); b++) {
            QHash<int, const Row *> rb;
            for (const Row &r : _veh[b].rows) rb[qRound(r.t * 10)] = &r;
            double minH = kNaN, min3 = kNaN, tMin = kNaN;
            QVariantList series;
            int k = 0;
            for (const Row &r : _veh[a].rows) {
                const Row *o = rb.value(qRound(r.t * 10), nullptr);
                if (!o || std::isnan(r.lat) || std::isnan(o->lat) || !(r.armed || o->armed)) continue;
                const double dh = haversine(r.lat, r.lon, o->lat, o->lon);
                const double dz = (std::isnan(r.alt) || std::isnan(o->alt)) ? 0.0 : double(r.alt - o->alt);
                const double d3 = std::sqrt(dh * dh + dz * dz);
                if (std::isnan(minH) || dh < minH) { minH = dh; tMin = r.t; }
                if (std::isnan(min3) || d3 < min3) min3 = d3;
                if (k++ % 2 == 0) series << QVariant(QVariantList{r.t, dh, dz});
            }
            QVariantMap p;
            p[QStringLiteral("a")] = _veh[a].sysid;
            p[QStringLiteral("b")] = _veh[b].sysid;
            p[QStringLiteral("minHorizontal")] = std::isnan(minH) ? QVariant() : QVariant(minH);
            p[QStringLiteral("min3d")] = std::isnan(min3) ? QVariant() : QVariant(min3);
            p[QStringLiteral("tMin")] = std::isnan(tMin) ? QVariant() : QVariant(tMin);
            p[QStringLiteral("series")] = series;
            _pairV << p;
        }
    }
    int byLevel[5] = {0, 0, 0, 0, 0};
    for (const QVariant &e : std::as_const(_evV)) {
        const QVariantMap m = e.toMap();
        if (m.value(QStringLiteral("source")).toString() == QLatin1String("ALERT")) byLevel[std::clamp(m.value(QStringLiteral("level")).toInt(), 0, 4)]++;
    }
    _duration = tMax;
    _summary[QStringLiteral("duration")] = tMax;
    _summary[QStringLiteral("vehicles")] = _veh.size();
    _summary[QStringLiteral("acactInterventions")] = interventions;
    _summary[QStringLiteral("acactTime")] = ownTime;
    _summary[QStringLiteral("alerts")] = QVariantList{byLevel[1], byLevel[2], byLevel[3], byLevel[4]};
    _extent[QStringLiteral("latMin")] = latMin; _extent[QStringLiteral("latMax")] = latMax;
    _extent[QStringLiteral("lonMin")] = lonMin; _extent[QStringLiteral("lonMax")] = lonMax;
    _extent[QStringLiteral("altMax")] = altMax;
}

QVariantList MLFlightRecords::stateAt(double t) const
{
    QVariantList out;
    for (const Veh &v : _veh) {
        if (v.rows.isEmpty()) continue;
        auto it = std::upper_bound(v.rows.begin(), v.rows.end(), t, [](double x, const Row &r) { return x < r.t; });
        const Row &r = it == v.rows.begin() ? v.rows.first() : *(it - 1);   // before the first sample: the first
        if (std::isnan(r.lat)) continue;
        QVariantMap m;
        m[QStringLiteral("sysid")] = v.sysid;
        m[QStringLiteral("id")] = QStringLiteral("D%1").arg(v.sysid);
        m[QStringLiteral("lat")] = r.lat; m[QStringLiteral("lon")] = r.lon; m[QStringLiteral("alt")] = std::isnan(r.alt) ? 0.0 : double(r.alt);
        m[QStringLiteral("hdg")] = r.hdg; m[QStringLiteral("roll")] = r.roll; m[QStringLiteral("pitch")] = r.pitch;
        m[QStringLiteral("gs")] = r.gs; m[QStringLiteral("pct")] = r.pct; m[QStringLiteral("mode")] = r.mode;
        m[QStringLiteral("lost")] = bool(r.lost); m[QStringLiteral("own")] = bool(r.own); m[QStringLiteral("armed")] = bool(r.armed);
        m[QStringLiteral("fresh")] = !r.lost;
        out << m;
    }
    return out;
}

QVariantList MLFlightRecords::geoTracks() const
{
    QVariantList out;
    for (const Veh &v : _veh) {
        QVariantList pts, path, ownPaths, cur;
        for (int i = 0; i < v.rows.size(); i++) {
            const Row &r = v.rows[i];
            if (std::isnan(r.lat)) continue;
            if (i % 2 == 0) pts << QVariant(QVariantList{r.t, r.lat, r.lon, std::isnan(r.alt) ? 0.0 : double(r.alt), int(r.own)});
            if (r.armed && i % 2 == 0) path << QVariant::fromValue(QGeoCoordinate(r.lat, r.lon));
            // ACACT-controlled stretches (every sample, so short avoidances are not lost)
            if (r.own) {
                cur << QVariant::fromValue(QGeoCoordinate(r.lat, r.lon));
            } else if (!cur.isEmpty()) {
                cur << QVariant::fromValue(QGeoCoordinate(r.lat, r.lon));
                ownPaths << QVariant(cur);
                cur.clear();
            }
        }
        if (cur.size() > 1) ownPaths << QVariant(cur);
        QVariantMap m;
        m[QStringLiteral("sysid")] = v.sysid;
        m[QStringLiteral("id")] = QStringLiteral("D%1").arg(v.sysid);
        m[QStringLiteral("points")] = pts;
        m[QStringLiteral("path")] = path;
        m[QStringLiteral("ownPaths")] = ownPaths;
        out << m;
    }
    return out;
}

QString MLFlightRecords::exportCsv(const QString &path)
{
    if (!loaded()) return QString();
    const QString p = path.isEmpty() ? QDir(_dir).filePath(QStringLiteral("summary_%1.csv").arg(_stamp)) : path;
    QFile f(p);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return QString();
    QTextStream ts(&f);
    ts.setEncoding(QStringConverter::Utf8);
    ts.setGenerateByteOrderMark(true);   // so Excel reads Korean text
    auto cell = [](const QVariant &v, int d) { return v.isValid() && !v.isNull() ? QString::number(v.toDouble(), 'f', d) : tr("미기록"); };
    ts << tr("기록,%1\n종류,%2\nGCS 버전,%3\n시험명,%4\n시험 목적,%5\n장소,%6\n운용자,%7\n")
              .arg(_stamp, _meta.value(QStringLiteral("kind")).toString(), _meta.value(QStringLiteral("gcsVersion")).toString(),
                   _meta.value(QStringLiteral("title")).toString(), _meta.value(QStringLiteral("purpose")).toString(),
                   _meta.value(QStringLiteral("site")).toString(), _meta.value(QStringLiteral("operator")).toString());
    ts << tr("\n기체,기록 표본,시동 시간 s,이동 거리 m,최고 고도 m,평균 속도 m/s,최고 속도 m/s,배터리 시작 %,배터리 끝 %,최저 전압 V,최소 위성,최대 HDOP,통신 두절 횟수,통신 두절 s,ACACT 개입,ACACT 제어 s\n");
    for (const QVariant &x : std::as_const(_vehV)) {
        const QVariantMap v = x.toMap();
        ts << QStringLiteral("UAV %1").arg(v.value(QStringLiteral("sysid")).toInt(), 2, 10, QLatin1Char('0')) << ','
           << v.value(QStringLiteral("samples")).toInt() << ',' << cell(v.value(QStringLiteral("armedTime")), 1) << ','
           << cell(v.value(QStringLiteral("distance")), 1) << ',' << cell(v.value(QStringLiteral("maxAlt")), 1) << ','
           << cell(v.value(QStringLiteral("meanSpeed")), 2) << ',' << cell(v.value(QStringLiteral("maxSpeed")), 2) << ','
           << cell(v.value(QStringLiteral("battStart")), 0) << ',' << cell(v.value(QStringLiteral("battEnd")), 0) << ','
           << cell(v.value(QStringLiteral("voltMin")), 2) << ',' << cell(v.value(QStringLiteral("minSats")), 0) << ','
           << cell(v.value(QStringLiteral("maxHdop")), 2) << ',' << v.value(QStringLiteral("linkLost")).toInt() << ','
           << cell(v.value(QStringLiteral("linkLostTime")), 1) << ',' << v.value(QStringLiteral("acactInterventions")).toInt() << ','
           << cell(v.value(QStringLiteral("acactTime")), 1) << '\n';
    }
    ts << tr("\n기체 쌍,최소 수평 이격 m,최소 3D 이격 m,시각 s\n");
    for (const QVariant &x : std::as_const(_pairV)) {
        const QVariantMap p = x.toMap();
        ts << QStringLiteral("UAV %1 - UAV %2").arg(p.value(QStringLiteral("a")).toInt(), 2, 10, QLatin1Char('0')).arg(p.value(QStringLiteral("b")).toInt(), 2, 10, QLatin1Char('0'))
           << ',' << cell(p.value(QStringLiteral("minHorizontal")), 2) << ',' << cell(p.value(QStringLiteral("min3d")), 2) << ',' << cell(p.value(QStringLiteral("tMin")), 1) << '\n';
    }
    ts << tr("\n시각 s,시각,중요도,출처,기체,내용\n");
    for (const QVariant &x : std::as_const(_evV)) {
        const QVariantMap e = x.toMap();
        ts << e.value(QStringLiteral("t")).toString() << ',' << e.value(QStringLiteral("time")).toString() << ',' << e.value(QStringLiteral("level")).toInt() << ','
           << e.value(QStringLiteral("source")).toString() << ',' << e.value(QStringLiteral("sysid")).toInt() << ",\"" << e.value(QStringLiteral("text")).toString() << "\"\n";
    }
    return p;
}

// ---- report drawing -----------------------------------------------------------------------------
void MLFlightRecords::_drawMap(QPainter &p, const QRectF &rc) const
{
    p.save();
    p.setPen(QPen(QColor(QStringLiteral("#C9CED4")), 0.8));
    p.setBrush(QColor(QStringLiteral("#F6F7F8")));
    p.drawRect(rc);
    const double la0 = _extent.value(QStringLiteral("latMin")).toDouble(), la1 = _extent.value(QStringLiteral("latMax")).toDouble();
    const double lo0 = _extent.value(QStringLiteral("lonMin")).toDouble(), lo1 = _extent.value(QStringLiteral("lonMax")).toDouble();
    if (la1 < la0) { p.restore(); return; }
    const double mlat = (la0 + la1) / 2, kx = std::cos(qDegreesToRadians(mlat)) * 111320.0, ky = 110574.0;
    const double w = std::max(20.0, (lo1 - lo0) * kx), h = std::max(20.0, (la1 - la0) * ky);
    const double s = std::min((rc.width() - 30) / w, (rc.height() - 30) / h);
    const QPointF c = rc.center();
    auto pt = [&](double lat, double lon) { return QPointF(c.x() + ((lon - (lo0 + lo1) / 2) * kx) * s, c.y() - ((lat - mlat) * ky) * s); };
    static const QColor cols[] = {QColor("#1F6FB2"), QColor("#2E8B57"), QColor("#8A4FBF"), QColor("#B5651D"), QColor("#00838F"), QColor("#6D4C41")};
    for (int i = 0; i < _veh.size(); i++) {
        const Veh &v = _veh[i];
        for (int k = 1; k < v.rows.size(); k++) {
            const Row &a = v.rows[k - 1], &b = v.rows[k];
            if (std::isnan(a.lat) || std::isnan(b.lat) || !b.armed) continue;
            p.setPen(QPen(b.own ? QColor(QStringLiteral("#C62828")) : cols[i % 6], b.own ? 2.2 : 1.4));
            p.drawLine(pt(a.lat, a.lon), pt(b.lat, b.lon));
        }
        for (const Row &r : v.rows) {
            if (!std::isnan(r.lat)) {
                p.setPen(Qt::NoPen);
                p.setBrush(cols[i % 6]);
                p.drawEllipse(pt(r.lat, r.lon), 3, 3);
                QFont f = p.font(); f.setPointSizeF(7); f.setBold(true); p.setFont(f);
                p.setPen(cols[i % 6]);
                p.drawText(pt(r.lat, r.lon) + QPointF(5, -4), QStringLiteral("UAV %1").arg(v.sysid, 2, 10, QLatin1Char('0')));
                break;
            }
        }
    }
    // scale bar
    const double bar = std::pow(10.0, std::floor(std::log10(std::max(1.0, w / 4))));
    p.setPen(QPen(QColor(QStringLiteral("#3A4148")), 1.2));
    const QPointF b0(rc.left() + 14, rc.bottom() - 14);
    p.drawLine(b0, b0 + QPointF(bar * s, 0));
    QFont f = p.font(); f.setPointSizeF(6.8); f.setBold(false); p.setFont(f);
    p.drawText(b0 + QPointF(0, -4), QStringLiteral("%1 m").arg(bar, 0, 'f', 0));
    p.drawText(QRectF(rc.right() - 30, rc.top() + 6, 24, 14), Qt::AlignCenter, QStringLiteral("N ↑"));
    p.restore();
}

// what: 0 altitude, 1 speed, 2 battery %, 3 separation
void MLFlightRecords::_drawChart(QPainter &p, const QRectF &rc, int what) const
{
    p.save();
    p.setPen(QPen(QColor(QStringLiteral("#C9CED4")), 0.8));
    p.setBrush(Qt::NoBrush);
    p.drawRect(rc);
    const double t1 = std::max(1.0, _duration);
    double yMax = what == 2 ? 100.0 : 1.0;
    QVector<QVector<QPointF>> lines;
    if (what == 3) {
        for (const QVariant &x : _pairV) {
            QVector<QPointF> l;
            for (const QVariant &s : x.toMap().value(QStringLiteral("series")).toList()) {
                const QVariantList r = s.toList();
                if (r.size() < 2) continue;
                l << QPointF(r[0].toDouble(), r[1].toDouble());
                yMax = std::max(yMax, r[1].toDouble());
            }
            lines << l;
        }
    } else {
        for (const QVariant &x : _vehV) {
            QVector<QPointF> l;
            for (const QVariant &s : x.toMap().value(QStringLiteral("series")).toList()) {
                const QVariantList r = s.toList();
                if (r.size() < 4) continue;
                const QVariant v = r[what == 0 ? 1 : (what == 1 ? 2 : 3)];
                if (!v.isValid() || v.isNull()) continue;
                l << QPointF(r[0].toDouble(), v.toDouble());
                if (what != 2) yMax = std::max(yMax, v.toDouble());
            }
            lines << l;
        }
    }
    yMax = what == 2 ? 100.0 : std::ceil(yMax * 1.15);
    const QRectF pl = rc.adjusted(34, 8, -8, -18);
    QFont f = p.font(); f.setPointSizeF(6.5); f.setBold(false); p.setFont(f);
    for (int g = 0; g <= 4; g++) {
        const double y = pl.bottom() - pl.height() * g / 4;
        p.setPen(QPen(QColor(QStringLiteral("#E3E6E9")), 0.6));
        p.drawLine(QPointF(pl.left(), y), QPointF(pl.right(), y));
        p.setPen(QColor(QStringLiteral("#4A525A")));
        p.drawText(QRectF(rc.left(), y - 7, 30, 14), Qt::AlignRight | Qt::AlignVCenter, QString::number(yMax * g / 4, 'f', yMax < 20 ? 1 : 0));
    }
    for (int g = 0; g <= 5; g++) {
        const double x = pl.left() + pl.width() * g / 5;
        p.drawText(QRectF(x - 20, pl.bottom() + 2, 40, 14), Qt::AlignCenter, QStringLiteral("%1 s").arg(t1 * g / 5, 0, 'f', 0));
    }
    static const QColor cols[] = {QColor("#1F6FB2"), QColor("#2E8B57"), QColor("#8A4FBF"), QColor("#B5651D"), QColor("#00838F"), QColor("#6D4C41")};
    for (int i = 0; i < lines.size(); i++) {
        p.setPen(QPen(cols[i % 6], 1.3));
        QPainterPath path;
        bool first = true;
        for (const QPointF &q : lines[i]) {
            const QPointF s(pl.left() + pl.width() * q.x() / t1, pl.bottom() - pl.height() * std::clamp(q.y() / yMax, 0.0, 1.0));
            if (first) { path.moveTo(s); first = false; } else { path.lineTo(s); }
        }
        p.drawPath(path);
    }
    p.restore();
}

QString MLFlightRecords::exportPdf(const QString &path)
{
    if (!loaded()) return QString();
    const QString out = path.isEmpty() ? QDir(_dir).filePath(QStringLiteral("report_%1.pdf").arg(_stamp)) : path;
    QPdfWriter w(out);
    w.setPageSize(QPageSize(QPageSize::A4));
    w.setPageMargins(QMarginsF(16, 14, 16, 14), QPageLayout::Millimeter);
    w.setResolution(144);
    w.setTitle(tr("MOBILITY LAB 비행시험 결과 보고서 %1").arg(_stamp));
    w.setCreator(QStringLiteral("MobilityLab GCS " ML_GCS_VERSION));
    QPainter p(&w);
    if (!p.isActive()) return QString();
    const QRectF page(0, 0, p.viewport().width() * 72.0 / 144.0, p.viewport().height() * 72.0 / 144.0);
    p.scale(144.0 / 72.0, 144.0 / 72.0);

    // MOBILITY LAB technical report: charcoal text, red only as the brand accent (rule, section
    // numbers), never for data — red prints purple on the office printer, so meaning never rests on it
    const QColor ink(QStringLiteral("#14171A")), sub(QStringLiteral("#3E464E")), red(QStringLiteral("#D80E18")), charcoal(QStringLiteral("#22272C")),
                 hair(QStringLiteral("#C9CED4")), fill(QStringLiteral("#F1F3F5"));
    const QString sans = QStringLiteral("IBM Plex Sans KR");
    auto font = [&](double pt, bool bold = false) { QFont f(sans); f.setPointSizeF(pt); f.setBold(bold); p.setFont(f); };
    const bool demo = _meta.value(QStringLiteral("kind")).toString() == QLatin1String("demo");
    const QString docNo = QStringLiteral("ML-FT-%1").arg(_stamp);
    QSvgRenderer logo(QStringLiteral(":/MobilityLab/logo.svg"));
    double y = 0;
    int pageNo = 1;
    auto miss = [&](const QVariant &v, int d, const QString &u) { return v.isValid() && !v.isNull() ? QString::number(v.toDouble(), 'f', d) + u : tr("미기록"); };
    auto userField = [&](const char *k) { const QString s = _meta.value(QString::fromLatin1(k)).toString().trimmed(); return s.isEmpty() ? tr("미입력") : s; };

    auto chrome = [&]() {
        // header: logo, wordmark, document number; a thin red rule under it
        if (logo.isValid()) logo.render(&p, QRectF(0, 0, 22, 22));
        font(9, true); p.setPen(ink);
        p.drawText(QRectF(28, 0, 200, 22), Qt::AlignLeft | Qt::AlignVCenter, QStringLiteral("MOBILITY LAB"));
        font(7); p.setPen(sub);
        p.drawText(QRectF(0, 0, page.width(), 22), Qt::AlignRight | Qt::AlignVCenter, docNo);
        p.fillRect(QRectF(0, 28, 46, 2), red);
        p.fillRect(QRectF(46, 28.6, page.width() - 46, 0.8), hair);
        // footer
        font(6.8); p.setPen(sub);
        p.drawText(QRectF(0, page.height() - 16, page.width(), 14), Qt::AlignLeft | Qt::AlignVCenter, tr("MOBILITY LAB 연구개발팀 · MobilityLab GCS %1 · 자동 생성 — 시험 책임자 확인 전에는 참고 자료").arg(QStringLiteral(ML_GCS_VERSION)));
        p.drawText(QRectF(0, page.height() - 16, page.width(), 14), Qt::AlignRight | Qt::AlignVCenter, QStringLiteral("%1").arg(pageNo));
        if (demo) {
            p.save();
            p.translate(page.center());
            p.rotate(-30);
            QFont wf(sans); wf.setPointSizeF(50); wf.setBold(true); p.setFont(wf);
            p.setPen(QColor(0, 0, 0, 30));
            p.drawText(QRectF(-page.width(), -60, page.width() * 2, 120), Qt::AlignCenter, tr("데모 · 실제 시험 기록 아님"));
            p.restore();
        }
        y = 44;
    };
    auto newPage = [&]() { w.newPage(); pageNo++; chrome(); };
    auto need = [&](double h) { if (y + h > page.height() - 26) newPage(); };
    int sec = 0;
    auto section = [&](const QString &t) {
        need(40);
        y += 8; sec++;
        font(8, true); p.setPen(red);
        p.drawText(QRectF(0, y, 24, 20), Qt::AlignLeft | Qt::AlignVCenter, QStringLiteral("%1").arg(sec, 2, 10, QLatin1Char('0')));
        font(11, true); p.setPen(ink);
        p.drawText(QRectF(24, y, page.width() - 24, 20), Qt::AlignLeft | Qt::AlignVCenter, t);
        y += 26;
    };
    // key–value grid in two columns
    auto kv = [&](const QList<QPair<QString, QString>> &items) {
        const double cw = page.width() / 2, rh = 17;
        for (int i = 0; i < items.size(); i++) {
            if (i % 2 == 0) need(rh);
            const double x = (i % 2) * cw, yy = y;
            font(7.4); p.setPen(sub);
            p.drawText(QRectF(x, yy, 92, rh), Qt::AlignLeft | Qt::AlignVCenter, items[i].first);
            font(8.4); p.setPen(ink);
            p.drawText(QRectF(x + 92, yy, cw - 100, rh), Qt::AlignLeft | Qt::AlignVCenter, items[i].second);
            if (i % 2 == 1 || i == items.size() - 1) {
                p.setPen(QPen(hair, 0.5));
                p.drawLine(QPointF(0, y + rh), QPointF(page.width(), y + rh));
                y += rh;
            }
        }
        y += 6;
    };
    auto table = [&](const QStringList &heads, const QList<QStringList> &rows, const QList<double> &ws) {
        const double rh = 18;
        need(rh * 2);
        auto head = [&]() {
            p.fillRect(QRectF(0, y, page.width(), rh), charcoal);
            double x = 0; font(7.2, true); p.setPen(Qt::white);
            for (int c = 0; c < heads.size(); c++) { p.drawText(QRectF(x + 5, y, ws[c] * page.width() - 8, rh), Qt::AlignLeft | Qt::AlignVCenter, heads[c]); x += ws[c] * page.width(); }
            y += rh;
        };
        head();
        for (int r = 0; r < rows.size(); r++) {
            if (y + rh > page.height() - 26) { newPage(); head(); }
            if (r % 2 == 1) p.fillRect(QRectF(0, y, page.width(), rh), fill);
            double x = 0; font(7.6); p.setPen(ink);
            for (int c = 0; c < rows[r].size() && c < ws.size(); c++) { p.drawText(QRectF(x + 5, y, ws[c] * page.width() - 8, rh), Qt::AlignLeft | Qt::AlignVCenter, rows[r][c]); x += ws[c] * page.width(); }
            y += rh;
        }
        p.setPen(QPen(hair, 0.6));
        p.drawLine(QPointF(0, y), QPointF(page.width(), y));
        y += 8;
    };
    auto paragraph = [&](const QString &t, double pt = 8.2) {
        font(pt); p.setPen(ink);
        const QRectF br = p.boundingRect(QRectF(0, 0, page.width(), 1000), Qt::TextWordWrap, t);
        need(br.height() + 4);
        p.drawText(QRectF(0, y, page.width(), br.height() + 2), Qt::TextWordWrap, t);
        y += br.height() + 6;
    };

    // ---- cover block ---------------------------------------------------------------------------
    chrome();
    const QString kind = _meta.value(QStringLiteral("kind")).toString();
    const QString kindText = kind == QLatin1String("demo") ? tr("데모 (GCS 내장 시뮬레이션)") : (kind == QLatin1String("sim") ? tr("시뮬레이션 (SITL)") : tr("실비행"));
    font(7.5, true); p.setPen(red);
    p.drawText(QRectF(0, y, page.width(), 16), Qt::AlignLeft | Qt::AlignVCenter, tr("비행시험 결과 보고서"));
    y += 18;
    font(18, true); p.setPen(ink);
    const QString title = _meta.value(QStringLiteral("title")).toString().trimmed();
    p.drawText(QRectF(0, y, page.width(), 30), Qt::AlignLeft | Qt::AlignVCenter, title.isEmpty() ? tr("비행 기록 %1").arg(_stamp) : title);
    y += 36;
    const QDateTime started = QDateTime::fromString(_meta.value(QStringLiteral("started")).toString(), Qt::ISODate);
    kv({{tr("문서 번호"), docNo}, {tr("구분"), kindText},
        {tr("시험 일시"), started.isValid() ? started.toString(QStringLiteral("yyyy-MM-dd HH:mm")) : _stamp}, {tr("시험 장소"), userField("site")},
        {tr("운용자"), userField("operator")}, {tr("GCS 버전"), _meta.value(QStringLiteral("gcsVersion")).toString()}});

    // ---- 01 summary: automatic verdict vs the test lead's judgement --------------------------------
    section(tr("종합 결과"));
    {
        const QString j = _meta.value(QStringLiteral("judgement")).toString();
        const QString jText = j == QLatin1String("pass") ? tr("적합") : (j == QLatin1String("fail") ? tr("부적합") : (j == QLatin1String("hold") ? tr("보류") : tr("미판정")));
        // automatic part: only facts from the record
        int lost = 0, inter = 0;
        double minSep = kNaN;
        for (const QVariant &x : std::as_const(_vehV)) { lost += x.toMap().value(QStringLiteral("linkLost")).toInt(); inter += x.toMap().value(QStringLiteral("acactInterventions")).toInt(); }
        for (const QVariant &x : std::as_const(_pairV)) { const QVariant m = x.toMap().value(QStringLiteral("minHorizontal")); if (m.isValid() && !m.isNull()) minSep = std::isnan(minSep) ? m.toDouble() : std::min(minSep, m.toDouble()); }
        const QList<int> al = [&]() { QList<int> l; for (const QVariant &v : _summary.value(QStringLiteral("alerts")).toList()) l << v.toInt(); return l; }();
        const double bw = (page.width() - 10) / 2, bh = 92;
        need(bh + 10);
        p.setPen(QPen(hair, 0.8)); p.setBrush(fill);
        p.drawRect(QRectF(0, y, bw, bh));
        p.drawRect(QRectF(bw + 10, y, bw, bh));
        p.setBrush(Qt::NoBrush);
        font(7.2, true); p.setPen(sub);
        p.drawText(QRectF(10, y + 6, bw - 20, 14), Qt::AlignLeft, tr("자동 집계 (기록 기반)"));
        p.drawText(QRectF(bw + 20, y + 6, bw - 20, 14), Qt::AlignLeft, tr("시험 책임자 판단"));
        font(8.2); p.setPen(ink);
        p.drawText(QRectF(10, y + 24, bw - 20, bh - 28), Qt::TextWordWrap,
                   tr("비행 시간 %1 · 기체 %2대\n통신 두절 %3회 · ACACT 개입 %4회\n기체 간 최소 수평 이격 %5\n경고: 정보 %6 · 주의 %7 · 위험 %8 · 긴급 %9")
                       .arg(QStringLiteral("%1 s").arg(_duration, 0, 'f', 0)).arg(_veh.size()).arg(lost).arg(inter)
                       .arg(std::isnan(minSep) ? tr("해당 없음 (1기)") : QStringLiteral("%1 m").arg(minSep, 0, 'f', 1))
                       .arg(al.value(0)).arg(al.value(1)).arg(al.value(2)).arg(al.value(3)));
        font(14, true); p.setPen(ink);
        p.drawText(QRectF(bw + 20, y + 22, bw - 30, 26), Qt::AlignLeft | Qt::AlignVCenter, jText);
        font(8); p.setPen(ink);
        const QString jn = _meta.value(QStringLiteral("judgementNote")).toString().trimmed();
        p.drawText(QRectF(bw + 20, y + 50, bw - 30, bh - 54), Qt::TextWordWrap, jn.isEmpty() ? tr("시험 책임자가 기록 관리 화면에서 입력합니다.") : jn);
        y += bh + 8;
        font(7); p.setPen(sub);
        p.drawText(QRectF(0, y, page.width(), 24), Qt::TextWordWrap, tr("자동 집계는 GCS가 받은 텔레메트리(2 Hz)만으로 계산한 값이며 합격 여부를 판정하지 않습니다. 최종 판단은 시험 책임자가 합니다."));
        y += 26;
    }

    // ---- 02 overview -----------------------------------------------------------------------------
    section(tr("시험 개요"));
    kv({{tr("시험 목적"), userField("purpose")}, {tr("시험 방법"), userField("method")},
        {tr("시험 환경 · 조건"), userField("conditions")}, {tr("비고"), userField("notes")}});

    // ---- 03 vehicles -----------------------------------------------------------------------------
    section(tr("시험 기체 및 장비"));
    {
        QList<QStringList> rows;
        const QVariantMap vm = _meta.value(QStringLiteral("vehicles")).toMap();
        for (auto it = vm.begin(); it != vm.end(); ++it) {
            const QVariantMap v = it.value().toMap();
            rows << QStringList{QStringLiteral("UAV %1").arg(v.value(QStringLiteral("sysid")).toInt(), 2, 10, QLatin1Char('0')), v.value(QStringLiteral("type")).toString(),
                                v.value(QStringLiteral("firmware")).toString(), v.value(QStringLiteral("fwVersion")).toString()};
        }
        table({tr("기체"), tr("유형"), tr("FC 펌웨어"), tr("버전")}, rows, {0.2, 0.3, 0.3, 0.2});
    }

    // ---- 04 results per vehicle ------------------------------------------------------------------
    section(tr("주요 시험 결과"));
    {
        QList<QStringList> rows;
        for (const QVariant &x : std::as_const(_vehV)) {
            const QVariantMap v = x.toMap();
            rows << QStringList{QStringLiteral("UAV %1").arg(v.value(QStringLiteral("sysid")).toInt(), 2, 10, QLatin1Char('0')),
                                miss(v.value(QStringLiteral("armedTime")), 0, QStringLiteral(" s")), miss(v.value(QStringLiteral("distance")), 0, QStringLiteral(" m")),
                                miss(v.value(QStringLiteral("maxAlt")), 1, QStringLiteral(" m")),
                                miss(v.value(QStringLiteral("meanSpeed")), 1, QString()) + QStringLiteral(" / ") + miss(v.value(QStringLiteral("maxSpeed")), 1, QStringLiteral(" m/s")),
                                miss(v.value(QStringLiteral("battStart")), 0, QStringLiteral("%")) + QStringLiteral(" → ") + miss(v.value(QStringLiteral("battEnd")), 0, QStringLiteral("%")),
                                miss(v.value(QStringLiteral("voltMin")), 2, QStringLiteral(" V"))};
        }
        table({tr("기체"), tr("시동 시간"), tr("이동 거리"), tr("최고 고도"), tr("평균 / 최고 속도"), tr("배터리"), tr("최저 전압")}, rows, {0.12, 0.12, 0.13, 0.13, 0.2, 0.16, 0.14});
        QList<QStringList> rows2;
        for (const QVariant &x : std::as_const(_vehV)) {
            const QVariantMap v = x.toMap();
            rows2 << QStringList{QStringLiteral("UAV %1").arg(v.value(QStringLiteral("sysid")).toInt(), 2, 10, QLatin1Char('0')),
                                 miss(v.value(QStringLiteral("minSats")), 0, QString()), miss(v.value(QStringLiteral("maxHdop")), 1, QString()),
                                 QStringLiteral("%1 s").arg(v.value(QStringLiteral("noFixTime")).toDouble(), 0, 'f', 0),
                                 tr("%1회 · %2 s").arg(v.value(QStringLiteral("linkLost")).toInt()).arg(v.value(QStringLiteral("linkLostTime")).toDouble(), 0, 'f', 0),
                                 tr("%1회 · %2 s").arg(v.value(QStringLiteral("acactInterventions")).toInt()).arg(v.value(QStringLiteral("acactTime")).toDouble(), 0, 'f', 0)};
        }
        table({tr("기체"), tr("최소 위성"), tr("최대 HDOP"), tr("3D 고정 없음"), tr("통신 두절"), tr("ACACT 개입")}, rows2, {0.14, 0.14, 0.14, 0.16, 0.21, 0.21});
    }

    // ---- 05 flight path, charts --------------------------------------------------------------------
    section(tr("비행 경로"));
    {
        const double h = 250;
        need(h + 18);
        _drawMap(p, QRectF(0, y, page.width(), h));
        y += h + 4;
        font(7); p.setPen(sub);
        p.drawText(QRectF(0, y, page.width(), 14), Qt::AlignLeft, tr("기록 위치(2 Hz) · 굵은 선 = ACACT가 제어한 구간 · 배경 지도 없음"));
        y += 18;
    }
    auto chart = [&](const QString &t, int what) {
        need(150);
        font(8, true); p.setPen(ink);
        p.drawText(QRectF(0, y, page.width(), 14), Qt::AlignLeft, t);
        y += 16;
        _drawChart(p, QRectF(0, y, page.width(), 120), what);
        y += 128;
    };
    section(tr("고도 · 속도 · 배터리"));
    chart(tr("상대 고도 (m, 이륙점 기준)"), 0);
    chart(tr("지면 속도 (m/s)"), 1);
    chart(tr("배터리 잔량 (%)"), 2);
    if (!_pairV.isEmpty()) {
        section(tr("기체 간 이격 및 ACACT"));
        chart(tr("기체 쌍 수평 이격 (m)"), 3);
        QList<QStringList> rows;
        for (const QVariant &x : std::as_const(_pairV)) {
            const QVariantMap pv = x.toMap();
            rows << QStringList{QStringLiteral("UAV %1 – UAV %2").arg(pv.value(QStringLiteral("a")).toInt(), 2, 10, QLatin1Char('0')).arg(pv.value(QStringLiteral("b")).toInt(), 2, 10, QLatin1Char('0')),
                                miss(pv.value(QStringLiteral("minHorizontal")), 1, QStringLiteral(" m")), miss(pv.value(QStringLiteral("min3d")), 1, QStringLiteral(" m")),
                                miss(pv.value(QStringLiteral("tMin")), 0, QStringLiteral(" s"))};
        }
        table({tr("기체 쌍"), tr("최소 수평 이격"), tr("최소 3D 이격"), tr("시각")}, rows, {0.34, 0.22, 0.22, 0.22});
        const QStringList gl = _meta.value(QStringLiteral("guardLogs")).toStringList();
        paragraph(gl.isEmpty() ? tr("이 비행에는 ACACT 가드 기록이 없습니다(가드 정지).")
                               : tr("ACACT 가드 기록 %1 — 20 Hz 판단값과 개입 사유는 'ACACT 분석' 보고서에 있습니다. 위 이격은 GCS 기록 위치(2 Hz)로 계산한 값입니다.").arg(gl.join(QStringLiteral(", "))), 7.6);
    }

    // ---- events ---------------------------------------------------------------------------------
    section(tr("통신 · 경고 · 비행 모드 이력"));
    {
        QList<QStringList> rows;
        const QStringList lv{tr("정보"), tr("정보"), tr("주의"), tr("위험"), tr("긴급")};
        for (const QVariant &x : std::as_const(_evV)) {
            const QVariantMap e = x.toMap();
            rows << QStringList{e.value(QStringLiteral("time")).toString(), lv.value(std::clamp(e.value(QStringLiteral("level")).toInt(), 0, 4)),
                                e.value(QStringLiteral("sysid")).toInt() > 0 ? QStringLiteral("UAV %1").arg(e.value(QStringLiteral("sysid")).toInt(), 2, 10, QLatin1Char('0')) : QStringLiteral("—"),
                                e.value(QStringLiteral("text")).toString()};
            if (rows.size() >= 60) break;
        }
        if (rows.isEmpty()) {
            paragraph(tr("기록된 경고·이벤트가 없습니다."), 7.8);
        } else {
            table({tr("시각"), tr("중요도"), tr("기체"), tr("내용")}, rows, {0.12, 0.1, 0.12, 0.66});
            if (_evV.size() > 60) paragraph(tr("처음 60건만 표시 — 전체는 CSV 내보내기"), 7.2);
        }
    }

    // ---- notes, sign-off -------------------------------------------------------------------------
    section(tr("시험 특이사항"));
    paragraph(userField("notes"));
    section(tr("검토 및 확인"));
    {
        need(100);
        const double cw = page.width() / 3, hh = 20, bh = 64;
        const QStringList who{tr("시험 책임자"), tr("검토"), tr("승인")};
        for (int c = 0; c < 3; c++) {
            p.fillRect(QRectF(cw * c, y, cw - 6, hh), charcoal);
            font(7.6, true); p.setPen(Qt::white);
            p.drawText(QRectF(cw * c, y, cw - 6, hh), Qt::AlignCenter, who[c]);
            p.setPen(QPen(hair, 0.8)); p.setBrush(Qt::NoBrush);
            p.drawRect(QRectF(cw * c, y + hh, cw - 6, bh));
            font(6.8); p.setPen(sub);
            p.drawText(QRectF(cw * c + 6, y + hh, cw - 18, bh - 4), Qt::AlignLeft | Qt::AlignBottom, tr("성명 · 서명 · 일자"));
        }
        y += hh + bh + 8;
    }
    p.end();
    return out;
}
