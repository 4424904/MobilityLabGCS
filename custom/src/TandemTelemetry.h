#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QHash>
#include <QtCore/QJsonObject>
#include <QtCore/QList>
#include <QtCore/QLoggingCategory>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtCore/QVariant>

class Vehicle;
typedef struct __mavlink_message mavlink_message_t;

Q_DECLARE_LOGGING_CATEGORY(TandemTelemetryLog)

/// Collects tandem-helicopter specific telemetry (engine, rotors, drivetrain,
/// fuel, power) from MAVLink and evaluates caution/warning conditions.
///
/// Every value is stored under a short key (e.g. "eng.rpm", "rot.front").
/// Where each key comes from, its display range and its caution/warning zones
/// are all defined in tandem.json, so the mapping can follow the aircraft ICD
/// without code changes. A copy of tandem.json placed in the application data
/// folder overrides the built-in one.
class TandemTelemetry : public QObject
{
    Q_OBJECT

    Q_PROPERTY(int          revision        READ revision       NOTIFY revisionChanged)
    /// key -> latest value, only for values received within the stale timeout
    Q_PROPERTY(QVariantMap  values          READ values         NOTIFY revisionChanged)
    /// key -> level (1 normal, 2 caution, 3 warning) for fresh values
    Q_PROPERTY(QVariantMap  levels          READ levels         NOTIFY revisionChanged)
    /// key -> true for every value received at least once
    Q_PROPERTY(QVariantMap  seenKeys        READ seenKeys       NOTIFY revisionChanged)
    Q_PROPERTY(QVariantList alerts          READ alerts         NOTIFY alertsChanged)
    Q_PROPERTY(bool         masterWarning   READ masterWarning  NOTIFY alertsChanged)
    Q_PROPERTY(bool         masterCaution   READ masterCaution  NOTIFY alertsChanged)
    Q_PROPERTY(bool         anyWarning      READ anyWarning     NOTIFY alertsChanged)
    Q_PROPERTY(bool         anyCaution      READ anyCaution     NOTIFY alertsChanged)
    Q_PROPERTY(QString      configSource    READ configSource   CONSTANT)
    Q_PROPERTY(bool         provisionalLimits READ provisionalLimits CONSTANT)

public:
    explicit TandemTelemetry(QObject *parent = nullptr);
    ~TandemTelemetry() override;

    /// Called for every MAVLink message received from a vehicle.
    void handleMessage(Vehicle *vehicle, const mavlink_message_t &message);

    /// Latest value for key, or NaN when never received or older than the stale timeout.
    Q_INVOKABLE double value(const QString &key) const;
    /// True when a value was received for key within the stale timeout.
    Q_INVOKABLE bool fresh(const QString &key) const;
    /// True when a value was ever received for key since the GCS started.
    Q_INVOKABLE bool seen(const QString &key) const;
    /// 0 = no data, 1 = normal, 2 = caution, 3 = warning
    Q_INVOKABLE int level(const QString &key) const;
    /// Display spec for key: label, unit, min, max, decimals, zones [[from,to,level],...]
    Q_INVOKABLE QVariantMap spec(const QString &key) const;
    /// Mark every active alert as acknowledged (stops the master lamps flashing).
    Q_INVOKABLE void acknowledgeAll();

    int          revision() const { return _revision; }
    QVariantMap  values() const { return _valuesMap; }
    QVariantMap  levels() const { return _levelsMap; }
    QVariantMap  seenKeys() const { return _seenMap; }
    QVariantList alerts() const;
    bool         masterWarning() const;
    bool         masterCaution() const;
    bool         anyWarning() const;
    bool         anyCaution() const;
    QString      configSource() const { return _configSource; }
    bool         provisionalLimits() const { return _provisionalLimits; }

    enum Level { NoData = 0, Normal = 1, Caution = 2, Warning = 3 };
    Q_ENUM(Level)

signals:
    void revisionChanged();
    void alertsChanged();

private slots:
    void _tick();

private:
    struct Sample {
        double value = 0;
        qint64 time  = -1;   ///< _clock ms, -1 = never
    };

    struct Alert {
        QString id;
        int     level = 0;
        QString text;
        QString time;
        bool    acked = false;
    };

    void   _loadConfig();
    void   _resetForVehicle(Vehicle *vehicle);
    void   _set(const QString &key, double value);
    void   _setRpm(int index, double rpm);
    void   _updateDerived();
    bool   _isFresh(const Sample &sample) const;
    int    _levelFor(const QString &key, double value) const;
    void   _evaluateAlerts();

    QHash<QString, Sample>  _samples;
    QElapsedTimer           _clock;
    QTimer                  _timer;
    int                     _revision = 0;
    QVariantMap             _valuesMap;
    QVariantMap             _levelsMap;
    QVariantMap             _seenMap;

    // Configuration (tandem.json)
    QJsonObject             _items;
    QHash<QString, QString> _namedValueMap;     ///< NAMED_VALUE_FLOAT name -> key
    QString                 _rpmSource = QStringLiteral("auto"); ///< auto | rpm | raw_rpm
    int                     _rotorFrontIndex = 0;
    int                     _rotorRearIndex  = 1;
    int                     _mainBatteryId   = 0;
    int                     _auxBatteryId    = -1;
    int                     _fuelBatteryId   = -1;
    double                  _fuelCapacityL   = 0;
    double                  _staleMs         = 3000;
    double                  _splitMinRpm     = 100;
    bool                    _provisionalLimits = true;
    QString                 _configSource;
    QString                 _lostEngineText = QStringLiteral("Engine (ECU) data lost");
    QString                 _lostRotorText  = QStringLiteral("Rotor RPM data lost");

    QPointer<Vehicle>       _vehicle;
    QList<Alert>            _alerts;
};
