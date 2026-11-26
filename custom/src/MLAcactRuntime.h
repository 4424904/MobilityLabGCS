#pragma once
//
// MLAcactRuntime — ACACT Guard running inside the GCS.
//
// Replaces guard.py (vendor/acact_guard/rev1) for operation from the GCS:
// the decision logic is AcactCore (C++ port of core.py, verified identical to
// the original by tools/acact_compare); this class does what guard.py does
// around it, but over the GCS's own MAVLink links instead of mavsdk_server +
// mavlink-router:
//   - telemetry of every connected vehicle → DroneIn (demo frame F/R/U)
//   - 20 Hz guard loop: takeover (OFFBOARD + velocity), velocity updates,
//     release (back to MISSION), orphan-OFFBOARD safety net
//   - operator commands: hold all (h), resume (r), synchronised start (g/g!),
//     auto-advance, sequential arm + mission start, preflight check
//   - CSV log, event log, end-of-run summary
//   - control arbitration: the operator always wins (operatorCommand()),
//     a pilot mode change locks the vehicle out of the guard (as the original)
//   - stop / GCS exit: vehicles the guard is flying are put in HOLD; if the GCS
//     dies, the setpoint stream stops and PX4 falls back on its offboard-loss
//     failsafe (COM_OF_LOSS_T → Hold), exactly like the original design.
//
// ACACT support scope: PX4 multicopters (OFFBOARD velocity control), as the
// original. Other vehicles (ArduPilot, helicopters, fixed wing) are tracked as
// traffic: the guard avoids them but never takes control of them.
//
#include "acact/AcactCore.h"
#include "acact/AcactScenarios.h"

#include <QtCore/QElapsedTimer>
#include <QtCore/QtNumeric>
#include <QtCore/QFile>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTextStream>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

#include <array>
#include <functional>
#include <memory>

#include "MAVLinkLib.h"

class Vehicle;

class MLAcactRuntime : public QObject
{
    Q_OBJECT
    // state (names shared with the map layer / fleet lanes)
    Q_PROPERTY(bool         active          READ running        NOTIFY runningChanged)
    Q_PROPERTY(bool         running         READ running        NOTIFY runningChanged)
    Q_PROPERTY(bool         seen            READ seen           NOTIFY runningChanged)
    Q_PROPERTY(bool         guardEnabled    READ guardEnabled   NOTIFY updated)
    Q_PROPERTY(QVariantList drones          READ drones         NOTIFY updated)
    Q_PROPERTY(QVariantList pairs           READ pairs          NOTIFY updated)
    Q_PROPERTY(QVariantMap  site            READ site           NOTIFY siteChanged)
    Q_PROPERTY(QVariantMap  config          READ config         NOTIFY paramsChanged)
    Q_PROPERTY(bool         autoMode        READ autoMode       WRITE setAutoMode NOTIFY updated)
    Q_PROPERTY(QString      scenario        READ scenario       NOTIFY updated)
    Q_PROPERTY(QString      scenarioMode    READ scenarioMode   NOTIFY updated)
    Q_PROPERTY(int          avoiding        READ avoiding       NOTIFY updated)
    Q_PROPERTY(double       closest         READ closest        NOTIFY updated)
    Q_PROPERTY(int          worstLevel      READ worstLevel     NOTIFY updated)
    Q_PROPERTY(double       guardTime       READ guardTime      NOTIFY updated)
    Q_PROPERTY(QVariantList minSeparation   READ minSeparation  NOTIFY updated)
    Q_PROPERTY(QVariantList preflight       READ preflight      NOTIFY updated)
    Q_PROPERTY(bool         startInProgress READ startInProgress NOTIFY updated)
    Q_PROPERTY(QVariantList params          READ params         NOTIFY paramsChanged)
    Q_PROPERTY(QString      supportScope    READ supportScope   CONSTANT)
    Q_PROPERTY(QString      logDir          READ logDir         CONSTANT)
    Q_PROPERTY(QString      lastLogFile     READ lastLogFile    NOTIFY runningChanged)
    // scenarios (scenarios.py / plan_gen.py)
    Q_PROPERTY(QVariantList scenarios       READ scenarios      NOTIFY scenariosChanged)
    Q_PROPERTY(QString      profile         READ profile        WRITE setProfile NOTIFY paramsChanged)
    Q_PROPERTY(QStringList  profiles        READ profiles       CONSTANT)
    Q_PROPERTY(QString      busyText        READ busyText       NOTIFY updated)
    Q_PROPERTY(QString      activeIds       READ activeIds      NOTIFY runningChanged)

public:
    explicit MLAcactRuntime(QObject *parent = nullptr);
    ~MLAcactRuntime() override;

    bool running() const { return _running; }
    bool seen() const { return _seen; }
    bool guardEnabled() const { return _core ? _core->enabled : true; }
    QVariantList drones() const { return _dronesV; }
    QVariantList pairs() const { return _pairsV; }
    QVariantMap site() const;
    QVariantMap config() const;
    bool autoMode() const { return _auto; }
    void setAutoMode(bool on);
    QString scenario() const { return _scenario; }
    QString scenarioMode() const { return _scenarioMode; }
    int avoiding() const { return _avoiding; }
    double closest() const { return _closest; }
    int worstLevel() const { return _worstLevel; }
    double guardTime() const { return _running ? _now() : 0.0; }
    QVariantList minSeparation() const;
    QVariantList preflight() const { return _preflightV; }
    bool startInProgress() const { return _startQueue.size() > 0; }
    QVariantList params() const;
    QString supportScope() const;
    QString logDir() const;
    QString lastLogFile() const { return _logPath; }
    QVariantList scenarios() const;
    QString profile() const { return _profile; }
    void setProfile(const QString &p);
    QStringList profiles() const { return {QStringLiteral("hwaseong"), QStringLiteral("oregon"), QStringLiteral("oregon2")}; }
    QString busyText() const { return _busy; }
    QString activeIds() const;

    // ---- operation ----------------------------------------------------------
    /// Start guarding every connected vehicle (MAVLink system id n → "Dn").
    Q_INVOKABLE bool start();
    /// Stop: vehicles the guard is flying go to HOLD, summary is written.
    Q_INVOKABLE void stop();
    /// h — guard paused, every airborne vehicle (not under manual control) to HOLD
    Q_INVOKABLE void holdAll();
    /// r — guard active again, HOLD/OFFBOARD vehicles resume their mission
    Q_INVOKABLE void resume();
    /// g / g! — synchronised start from the LOITER_UNLIM wait points
    Q_INVOKABLE void sync(bool force);
    /// start — preflight, then arm + start mission one vehicle at a time (highest id first, 5 s apart)
    Q_INVOKABLE bool startFlight();
    /// abort a running startFlight sequence
    Q_INVOKABLE void abortStart();
    /// Recompute the preflight list now
    Q_INVOKABLE QVariantList runPreflight();

    /// Operator command to one vehicle from the GCS (command bar, 목표 조정 …):
    /// the operator always wins — if the guard is flying it, the guard lets go
    /// and leaves the vehicle alone until its mission is resumed.
    Q_INVOKABLE void operatorCommand(int sysid, const QString &what);
    Q_INVOKABLE bool owns(int sysid) const;

    /// Compatibility with the fleet-lane buttons: "h", "r", "g", "g!", "auto on|off", "start", "s"
    Q_INVOKABLE bool sendLine(const QString &line);
    Q_INVOKABLE QVariantMap droneForSysid(int sysid) const;

    // ---- settings -------------------------------------------------------------
    Q_INVOKABLE void setParam(const QString &key, double value);
    Q_INVOKABLE void resetParams();
    /// Demo frame origin and forward bearing. Without a site the first vehicle position is used (bearing 0).
    Q_INVOKABLE void setSite(double lat, double lon, double bearingDeg, double radius = 25.0);
    /// plan_gen.py --from-vehicles: demo frame from the vehicles' home positions; bearingDeg < 0 → heading average
    Q_INVOKABLE void setSiteFromVehicles(double bearingDeg);
    /// load <name> <demo|rehearsal>: build the scenario missions (scenarios.py), upload and verify them
    Q_INVOKABLE void loadScenario(const QString &name, const QString &mode);
    Q_INVOKABLE void clearSite();

signals:
    void runningChanged();
    void updated();
    void paramsChanged();
    void siteChanged();
    void scenariosChanged();
    void guardEvent(int seq, double time, const QString &who, const QString &text);

private slots:
    void _tick();
    void _vehicleAdded(Vehicle *vehicle);
    void _vehicleRemoved(Vehicle *vehicle);
    void _startNext();

private:
    struct VS;

    double _now() const { return _clock.isValid() ? _clock.elapsed() / 1000.0 : 0.0; }
    void _event(const QString &who, const QString &text);
    VS *_vs(const QString &id);
    VS *_vsBySysid(int sysid);
    void _attach(Vehicle *vehicle);
    void _onMessage(VS *d, const mavlink_message_t &message);
    void _rebuildCore();
    acact::Config _effectiveParams(int n) const;

    // vehicle commands
    void _sendSetpoint(VS *d);
    void _setMode(VS *d, int mainMode, int subMode);   // PX4 custom mode via MAV_CMD_DO_SET_MODE
    void _hold(VS *d);
    void _startMission(VS *d);
    void _setCurrent(VS *d, int seq);
    /// rev1: MISSION_SET_CURRENT once per try and check progress (≤3 tries); done(ok, error)
    void _setCurrentChecked(VS *d, int k, std::function<void(bool, QString)> done);
    /// rev1 goto_next_item: skip DO items (apply a skipped speed change directly), then set current
    void _gotoNextItem(VS *d, std::function<void(bool, QString)> done);
    void _uploadNext(QStringList ids, QString name, QString mode, bool ok);
    QStringList _activeIdList() const;               // controllable PX4 vehicles D1..D4 (scenario fleet)
    std::array<double, 2> _homeLl(const QString &id) const;   // site.json homes, else planned home
    acact::Config _cfg() const { return _core ? _core->config() : _effectiveParams(std::max(2, static_cast<int>(_vs_.size()))); }
    void _takeover(VS *d, const acact::Vec3 &v);
    void _release(VS *d);
    bool _canTake(VS *d);
    void _stopHold(VS *d);

    // guard.py pieces
    std::pair<int, int> _goalOf(VS *d) const;           // (item index, previous position item index)
    void _syncState(QList<VS *> &ready, QList<VS *> &notReady, bool &landing) const;
    void _autoTick(double t);
    void _writeLog(double t, const std::vector<acact::DroneIn> &ins);
    void _publish(const std::vector<acact::DroneIn> &ins);
    void _writeSummary();
    void _loadSettings();

    QList<VS *>                         _vs_;
    std::unique_ptr<acact::GuardCore> _core;
    std::unique_ptr<acact::Frame>       _frame;
    bool        _siteSet = false;
    double      _siteRadius = 25.0;
    QTimer      _timer;
    QElapsedTimer _clock;
    bool        _running = false;
    bool        _seen = false;
    long        _k = 0;
    bool        _auto = true;
    double      _lastSyncT = -1e9;
    double      _autoSince = -1;
    double      _autoBadSince = -1;
    double      _autoToldAt = -1e9;
    bool        _autoLandTold = false;
    QString     _scenario;
    QString     _scenarioMode;
    int         _avoiding = 0;
    double      _closest = qQNaN();
    int         _worstLevel = 0;
    QVariantList _dronesV;
    QVariantList _pairsV;
    QVariantList _preflightV;
    int         _eventSeq = 0;
    int         _tickErrors = 0;
    QList<QString> _startQueue;
    QTimer      _startTimer;
    QMap<QString, double> _paramOverrides;

    QString     _profile = QStringLiteral("oregon");   // config.py PROFILE default
    QString     _busy;
    QMap<QString, QPair<double, double>> _siteHomes;   // site.json "homes"

    QFile       _logFile;
    QFile       _evFile;
    QString     _logPath;
    QString     _sumPath;
};
