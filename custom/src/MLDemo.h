#pragma once

// MobilityLab GCS — built-in demonstration mode.
//
// Simulated PX4 multicopters inside the GCS process, reached through their own in-process link
// (MLDemoLink). The GCS talks to them with ordinary MAVLink — the same code paths as with real
// aircraft (instruments, plan upload, guided commands, the native ACACT guard) — so what the demo
// shows is the real software at work, only the aircraft are simulated.
//
// Separation from real aircraft is structural, not a UI switch:
//   * while the demo runs, LinkManager's link gate refuses every other link (UDP, serial, TCP,
//     Bluetooth, auto-connect), and all links that were open are closed first; real aircraft cannot
//     connect, so no command can reach one;
//   * the demo link has no I/O to the outside (no socket, no port); bytes go to the simulator only;
//   * demo vehicles are marked (sim = 2) — ACACT never records a demo flight as a SITL validation,
//     guard logs are tagged "demo" and reports carry a "demo · not test evidence" watermark.

#include "LinkConfiguration.h"
#include "LinkInterface.h"
#include "MAVLinkLib.h"

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>

#include <memory>
#include <vector>

class MLDemoLinkConfiguration : public LinkConfiguration
{
    Q_OBJECT
public:
    explicit MLDemoLinkConfiguration(const QString &name, QObject *parent = nullptr) : LinkConfiguration(name, parent) {}
    LinkType type() const override { return LinkConfiguration::TypeLast; }   // built by MLDemo's link factory
    void loadSettings(QSettings &, const QString &) override {}
    void saveSettings(QSettings &, const QString &) const override {}
    QString settingsURL() const override { return QString(); }
    QString settingsTitle() const override { return tr("데모 링크"); }
};

/// One simulated multicopter (PX4 behaviour: modes, mission, offboard, failsafes, battery).
struct MLDemoVehicle
{
    int sysid = 1;
    double lat = 0, lon = 0, alt = 0;          // alt: above home [m]
    double homeLat = 0, homeLon = 0;
    double homeAmsl = 20.0;
    double vn = 0, ve = 0, vd = 0;             // velocity NED [m/s]
    double yaw = 0;                            // rad
    double roll = 0, pitch = 0;
    int main = 4, sub = 3;                     // PX4 main / auto sub mode (AUTO_LOITER)
    bool armed = false;
    bool inAir = false;
    double batt = 100.0;                       // %
    double cruise = 3.0;                       // mission horizontal speed [m/s]
    double takeoffAlt = 8.0;
    double rtlAlt = 20.0;
    // mission
    struct Item { int cmd = 16; int frame = 3; float p[4] = {0, 0, 0, 0}; double x = 0, y = 0; float z = 0; bool autoContinue = true; };
    std::vector<Item> mission;
    int cur = 0;
    double holdUntil = -1;                     // waypoint hold time
    double loiterLat = 0, loiterLon = 0, loiterAlt = 0;
    bool loiterSet = false;
    // offboard
    double spN = 0, spE = 0, spD = 0;
    double spT = -1e9;                         // time of last velocity setpoint
    double landedAt = -1;
    // link
    bool linkCut = false;
    uint8_t txSeq = 0;                         // MAVLink sequence of this vehicle
    int paramIdx = -1;                         // PARAM_REQUEST_LIST streaming position (-1 idle)
    bool warned30 = false, warned15 = false;
    double lastHb = -1;
    // mission upload in progress (GCS → vehicle)
    int upCount = -1, upNext = 0, upType = 0;
    std::vector<Item> upItems;
    double upT = 0;
    // parameters set by the GCS (name → value) on top of the defaults
    QHash<QString, double> paramOverride;
};

class MLDemoLink : public LinkInterface
{
    Q_OBJECT
public:
    MLDemoLink(SharedLinkConfigurationPtr &config, class MLDemo *demo);
    ~MLDemoLink() override;

    void disconnect() override;
    bool isConnected() const override { return _connected; }
    bool isSecureConnection() const override { return true; }   // in-process

    /// simulator → GCS
    void deliver(const mavlink_message_t &msg);
    uint8_t outChannel() const { return _outChan; }
    qint64 rxBytes() const { return _rxBytes; }
    qint64 rxMsgs() const { return _rxMsgs; }
    qint64 rxBad() const { return _rxBad; }

private slots:
    void _writeBytes(const QByteArray &bytes) override;

private:
    bool _connect() override;

    QPointer<class MLDemo> _demo;
    bool _connected = false;
    uint8_t _inChan = 0;
    uint8_t _outChan = 0;
    qint64 _rxBytes = 0, _rxMsgs = 0, _rxBad = 0;
};

class MLDemo : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         active      READ active     NOTIFY activeChanged)
    Q_PROPERTY(QString      scenario    READ scenario   NOTIFY activeChanged)
    Q_PROPERTY(QVariantList scenarios   READ scenarios  CONSTANT)
    Q_PROPERTY(QString      planDir     READ planDir    NOTIFY activeChanged)
    Q_PROPERTY(QVariantList vehicles    READ vehiclesV  NOTIFY tick)
    Q_PROPERTY(double       timeScale   READ timeScale  WRITE setTimeScale NOTIFY timeScaleChanged)

public:
    explicit MLDemo(QObject *parent = nullptr);
    ~MLDemo() override;

    bool active() const { return _active; }
    QString scenario() const { return _scenario; }
    QVariantList scenarios() const;
    QString planDir() const { return _planDir; }
    QVariantList vehiclesV() const;
    double timeScale() const { return _timeScale; }
    void setTimeScale(double s);

    /// scenario: single · duo · trio. Closes every real link first and keeps them closed until stop().
    Q_INVOKABLE bool start(const QString &scenario);
    // Non-empty while the demo must not start: a real vehicle is connected. The demo never
    // disconnects a real aircraft on its own (dropping the link of a flying aircraft is itself
    // a hazard); the operator disconnects it first.
    Q_INVOKABLE QString startBlockReason() const;
    Q_INVOKABLE void stop();
    /// simulate a telemetry link loss of one demo vehicle (both directions) / restore it
    Q_INVOKABLE void setLinkCut(int sysid, bool cut);
    /// is this vehicle one of the demo's (false for anything on a real link)
    Q_INVOKABLE bool isDemoSysid(int sysid) const;
    static bool isDemoLink(const LinkInterface *link);
    static MLDemo *instance() { return _instance; }

    /// GCS → simulator (called by the link)
    void receive(const mavlink_message_t &msg);

signals:
    void activeChanged();
    void tick();
    void timeScaleChanged();
    void notice(const QString &text);

private:
    void _step();
    void _stepVehicle(MLDemoVehicle &v, double dt);
    void _send(const MLDemoVehicle &v, mavlink_message_t &msg);
    void _sendTelemetry(MLDemoVehicle &v, bool fast, bool slow);
    void _sendHeartbeat(MLDemoVehicle &v);
    void _sendText(MLDemoVehicle &v, int severity, const QString &text);
    void _ack(MLDemoVehicle &v, int cmd, int result, int sysid, int compid);
    void _command(MLDemoVehicle &v, int cmd, const float p[7], double x, double y, int frame, int sysid, int compid);
    void _mission(MLDemoVehicle &v, const mavlink_message_t &msg);
    void _param(MLDemoVehicle &v, const mavlink_message_t &msg);
    void _sendParam(MLDemoVehicle &v, int index);
    void _setMode(MLDemoVehicle &v, int main, int sub);
    void _goToItem(MLDemoVehicle &v, int seq);
    void _writePlans(const QString &scenario);
    MLDemoVehicle *_veh(int sysid);
    double _now() const { return _simTime; }
    uint8_t _oc() const;

    static inline MLDemo *_instance = nullptr;
    struct Param { QString name; int type; double value; };
    std::vector<Param> _params;
    void _loadParams();

    bool _active = false;
    QString _scenario;
    QString _planDir;
    std::vector<MLDemoVehicle> _v;
    QTimer _timer;
    QElapsedTimer _wall;
    qint64 _lastWall = 0;
    double _simTime = 0;
    double _timeScale = 1.0;
    int _tickN = 0;
    std::shared_ptr<LinkInterface> _link;
    SharedLinkConfigurationPtr _config;
    QString _prevOpMode;
};
