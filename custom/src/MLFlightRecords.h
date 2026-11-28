// MobilityLab GCS — flight records (v1.2)
//
// Every flight is recorded, whether or not the ACACT guard runs: from the first arm until every
// vehicle has been disarmed for 20 s. Twice a second, for every connected vehicle, what QGC
// received (position, altitudes, speeds, attitude, battery, GNSS, link state, mode, arming) and the
// guard's phase for that vehicle. Alerts and operator events are added as they happen.
//
//   <base>/Flights/<stamp>/   real flights and SITL (kind "field" / "sim", from the declared operating mode)
//   <base>/Demo/<stamp>/      the built-in demo — kept apart, never listed with real flights by default
//       meta.json    kind, GCS version, vehicles (type, firmware), missions, guard log, user fields
//       track.csv    2 Hz samples
//       events.csv   alerts (raised / cleared), modes, arming, operator events
//
// Analysis and reports use only what is in these files; anything not recorded is reported as
// "미기록" (not recorded), never estimated. Nothing here sends anything to a vehicle.
#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QFile>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtCore/QVector>

class MLAcactRuntime;
class MLDemo;
class QPainter;
class QRectF;

class MLFlightRecords : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         recording   READ recording   NOTIFY recordingChanged)
    Q_PROPERTY(QString      current     READ current     NOTIFY recordingChanged)
    Q_PROPERTY(QString      baseDir     READ baseDir     WRITE setBaseDir NOTIFY baseDirChanged)
    Q_PROPERTY(QVariantList records     READ records     NOTIFY recordsChanged)
    Q_PROPERTY(bool         loaded      READ loaded      NOTIFY loadedChanged)
    Q_PROPERTY(QString      stamp       READ stamp       NOTIFY loadedChanged)
    Q_PROPERTY(QVariantMap  meta        READ meta        NOTIFY loadedChanged)
    Q_PROPERTY(QVariantList vehicles    READ vehicles    NOTIFY loadedChanged)   // per vehicle: metrics + series
    Q_PROPERTY(QVariantList pairs       READ pairs       NOTIFY loadedChanged)   // per pair: min separation + series
    Q_PROPERTY(QVariantList events      READ events      NOTIFY loadedChanged)
    Q_PROPERTY(QVariantMap  summary     READ summary     NOTIFY loadedChanged)
    Q_PROPERTY(double       duration    READ duration    NOTIFY loadedChanged)
    Q_PROPERTY(QVariantMap  extent      READ extent      NOTIFY loadedChanged)   // latMin latMax lonMin lonMax altMax

public:
    explicit MLFlightRecords(QObject *parent = nullptr);
    void attach(MLAcactRuntime *guard, MLDemo *demo);

    bool recording() const { return _rec; }
    QString current() const { return _rec ? _curStamp : QString(); }
    QString baseDir() const;
    void setBaseDir(const QString &dir);
    QVariantList records() const { return _records; }
    bool loaded() const { return !_stamp.isEmpty(); }
    QString stamp() const { return _stamp; }
    QVariantMap meta() const { return _meta; }
    QVariantList vehicles() const { return _vehV; }
    QVariantList pairs() const { return _pairV; }
    QVariantList events() const { return _evV; }
    QVariantMap summary() const { return _summary; }
    double duration() const { return _duration; }
    QVariantMap extent() const { return _extent; }

    /// list records: kind "" = real + SITL, "demo", "all"; text matches name, purpose, site, operator, notes, vehicles
    Q_INVOKABLE void refresh(const QString &kind = QString(), const QString &text = QString());
    Q_INVOKABLE bool load(const QString &stamp);
    Q_INVOKABLE void unload();
    /// user fields: title, purpose, site, operator, notes, judgement ("pass" | "fail" | "hold" | ""), judgementNote
    Q_INVOKABLE bool setUserFields(const QString &stamp, const QVariantMap &fields);
    /// replay: every vehicle at time t (seconds from the start)
    Q_INVOKABLE QVariantList stateAt(double t) const;
    /// add an event to the running record (alerts, operator actions). level 0 info … 4 emergency
    Q_INVOKABLE void event(int level, const QString &source, const QString &text, int sysid = 0);
    Q_INVOKABLE QString exportCsv(const QString &path = QString());
    Q_INVOKABLE QString exportPdf(const QString &path = QString());
    Q_INVOKABLE QString recordDir(const QString &stamp) const;

signals:
    void recordingChanged();
    void baseDirChanged();
    void recordsChanged();
    void loadedChanged();

private:
    struct Row {
        float t, lat, lon, alt, amsl, agl, gs, vs, hdg, roll, pitch, pct, volt, hdop;
        qint8 fix, sats;
        quint8 lost, armed, own;
        QString mode;
    };
    struct Veh {
        int sysid = 0;
        QVector<Row> rows;
    };

    void _tick();
    void _start();
    void _stop();
    QString _kindNow() const;
    QVariantMap _vehicleInfo() const;
    void _writeMeta(const QString &dir, const QVariantMap &m) const;
    QVariantMap _readMeta(const QString &dir) const;
    void _compute();
    void _drawMap(QPainter &p, const QRectF &rc) const;
    void _drawChart(QPainter &p, const QRectF &rc, int what) const;

    QPointer<MLAcactRuntime> _guard;
    QPointer<MLDemo> _demo;
    QTimer _timer;
    QElapsedTimer _clock;
    bool _rec = false;
    QString _curStamp, _curDir, _curKind;
    QFile _track, _events;
    double _lastArmed = 0;
    QVariantMap _curVeh;

    QVariantList _records;
    QString _stamp, _dir;
    QVariantMap _meta, _summary, _extent;
    QVariantList _vehV, _pairV, _evV;
    QVector<Veh> _veh;
    double _duration = 0;
};
