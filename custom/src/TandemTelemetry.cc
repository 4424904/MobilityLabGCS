#include "TandemTelemetry.h"

#include "MAVLinkLib.h"
#include "MultiVehicleManager.h"
#include "QGCLoggingCategory.h"
#include "Vehicle.h"

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QStandardPaths>
#include <QtCore/QtNumeric>

#include <algorithm>
#include <cmath>
#include <cstring>

QGC_LOGGING_CATEGORY(TandemTelemetryLog, "MobilityLab.TandemTelemetry")

namespace {
constexpr int kTickMs = 200;
const QString kBuiltinConfig = QStringLiteral(":/MobilityLab/tandem.json");
}

TandemTelemetry::TandemTelemetry(QObject *parent)
    : QObject(parent)
{
    _clock.start();
    _loadConfig();

    _timer.setInterval(kTickMs);
    (void) connect(&_timer, &QTimer::timeout, this, &TandemTelemetry::_tick);
    _timer.start();
}

TandemTelemetry::~TandemTelemetry() = default;

/*---------------------------------------------------------------------------*/
/* Configuration                                                             */
/*---------------------------------------------------------------------------*/

void TandemTelemetry::_loadConfig()
{
    QStringList candidates;
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (!dataDir.isEmpty()) {
        candidates << QDir(dataDir).filePath(QStringLiteral("tandem.json"));
    }
    candidates << kBuiltinConfig;

    for (const QString &path : std::as_const(candidates)) {
        QFile file(path);
        if (!file.exists() || !file.open(QIODevice::ReadOnly)) {
            continue;
        }
        QJsonParseError err{};
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            qCWarning(TandemTelemetryLog) << "Ignoring invalid config" << path << err.errorString();
            continue;
        }

        const QJsonObject root = doc.object();
        _items              = root.value(QStringLiteral("items")).toObject();
        _staleMs            = root.value(QStringLiteral("staleSeconds")).toDouble(3.0) * 1000.0;
        _provisionalLimits  = root.value(QStringLiteral("provisionalLimits")).toBool(true);

        const QJsonObject rpm = root.value(QStringLiteral("rotorRpm")).toObject();
        _rpmSource          = rpm.value(QStringLiteral("source")).toString(QStringLiteral("auto"));
        _rotorFrontIndex    = rpm.value(QStringLiteral("frontIndex")).toInt(0);
        _rotorRearIndex     = rpm.value(QStringLiteral("rearIndex")).toInt(1);
        _splitMinRpm        = rpm.value(QStringLiteral("splitMinRpm")).toDouble(100.0);

        const QJsonObject bat = root.value(QStringLiteral("battery")).toObject();
        _mainBatteryId      = bat.value(QStringLiteral("mainId")).toInt(0);
        _auxBatteryId       = bat.value(QStringLiteral("auxId")).toInt(-1);
        _fuelBatteryId      = bat.value(QStringLiteral("fuelId")).toInt(-1);
        _fuelCapacityL      = bat.value(QStringLiteral("fuelCapacityLiters")).toDouble(0.0);

        const QJsonObject texts = root.value(QStringLiteral("texts")).toObject();
        _lostEngineText     = texts.value(QStringLiteral("lostEngine")).toString(QStringLiteral("Engine (ECU) data lost"));
        _lostRotorText      = texts.value(QStringLiteral("lostRotor")).toString(QStringLiteral("Rotor RPM data lost"));

        _namedValueMap.clear();
        const QJsonObject named = root.value(QStringLiteral("namedValueFloat")).toObject();
        for (auto it = named.constBegin(); it != named.constEnd(); ++it) {
            _namedValueMap.insert(it.key(), it.value().toString());
        }

        _configSource = (path == kBuiltinConfig) ? QStringLiteral("built-in") : path;
        qCDebug(TandemTelemetryLog) << "Loaded config" << path << "items" << _items.count();
        return;
    }

    qCWarning(TandemTelemetryLog) << "No tandem.json found, telemetry panel will show no limits";
    _configSource = QStringLiteral("none");
}

/*---------------------------------------------------------------------------*/
/* MAVLink                                                                   */
/*---------------------------------------------------------------------------*/

void TandemTelemetry::handleMessage(Vehicle *vehicle, const mavlink_message_t &message)
{
    // Multi-vehicle: show only the active (selected) vehicle's powertrain data
    Vehicle *active = MultiVehicleManager::instance()->activeVehicle();
    if (!vehicle || (vehicle != active)) {
        return;
    }
    if (_vehicle != vehicle) {
        _resetForVehicle(vehicle);
    }

    switch (message.msgid) {
    case MAVLINK_MSG_ID_EFI_STATUS: {
        mavlink_efi_status_t efi{};
        mavlink_msg_efi_status_decode(&message, &efi);
        _set(QStringLiteral("eng.rpm"),       efi.rpm);
        _set(QStringLiteral("eng.cht"),       efi.cylinder_head_temperature);
        _set(QStringLiteral("eng.egt"),       efi.exhaust_gas_temperature);
        _set(QStringLiteral("eng.iat"),       efi.intake_manifold_temperature);
        _set(QStringLiteral("eng.thr"),       efi.throttle_position);
        _set(QStringLiteral("eng.load"),      efi.engine_load);
        _set(QStringLiteral("eng.flow"),      efi.fuel_flow * 60.0 / 1000.0);   // cm3/min -> L/h
        _set(QStringLiteral("eng.used"),      efi.fuel_consumed / 1000.0);      // cm3 -> L
        _set(QStringLiteral("eng.fuelPress"), efi.fuel_pressure);
        _set(QStringLiteral("eng.ignV"),      efi.ignition_voltage);
        if (efi.health != INT8_MAX) {
            _set(QStringLiteral("eng.health"), efi.health);
        }
        break;
    }
    case MAVLINK_MSG_ID_RPM: {
        if (_rpmSource == QStringLiteral("raw_rpm")) {
            break;
        }
        mavlink_rpm_t rpm{};
        mavlink_msg_rpm_decode(&message, &rpm);
        _setRpm(0, rpm.rpm1);
        _setRpm(1, rpm.rpm2);
        break;
    }
    case MAVLINK_MSG_ID_RAW_RPM: {
        if (_rpmSource == QStringLiteral("rpm")) {
            break;
        }
        mavlink_raw_rpm_t raw{};
        mavlink_msg_raw_rpm_decode(&message, &raw);
        _setRpm(raw.index, raw.frequency);
        break;
    }
    case MAVLINK_MSG_ID_BATTERY_STATUS: {
        mavlink_battery_status_t bat{};
        mavlink_msg_battery_status_decode(&message, &bat);

        double millivolts = 0;
        bool   anyCell    = false;
        for (int i = 0; i < 10; i++) {
            if (bat.voltages[i] != UINT16_MAX) {
                millivolts += bat.voltages[i];
                anyCell = true;
            }
        }
        for (int i = 0; i < 4; i++) {
            if ((bat.voltages_ext[i] != 0) && (bat.voltages_ext[i] != UINT16_MAX)) {
                millivolts += bat.voltages_ext[i];
            }
        }
        const double volts = anyCell ? millivolts / 1000.0 : qQNaN();

        if (bat.id == _mainBatteryId) {
            _set(QStringLiteral("pwr.main"), volts);
            if (bat.current_battery != -1) {
                _set(QStringLiteral("pwr.mainA"), bat.current_battery / 100.0);
            }
        }
        if (bat.id == _auxBatteryId) {
            _set(QStringLiteral("pwr.aux"), volts);
        }
        if ((bat.id == _fuelBatteryId) && (bat.battery_remaining >= 0)) {
            _set(QStringLiteral("fuel.pct"), bat.battery_remaining);
            if (_fuelCapacityL > 0) {
                _set(QStringLiteral("fuel.L"), _fuelCapacityL * bat.battery_remaining / 100.0);
            }
        }
        break;
    }
    case MAVLINK_MSG_ID_GENERATOR_STATUS: {
        mavlink_generator_status_t gen{};
        mavlink_msg_generator_status_decode(&message, &gen);
        _set(QStringLiteral("pwr.genA"), gen.load_current);
        _set(QStringLiteral("pwr.genV"), gen.bus_voltage);
        if (gen.generator_speed != UINT16_MAX) {
            _set(QStringLiteral("pwr.genRpm"), gen.generator_speed);
        }
        break;
    }
    case MAVLINK_MSG_ID_NAMED_VALUE_FLOAT: {
        mavlink_named_value_float_t nv{};
        mavlink_msg_named_value_float_decode(&message, &nv);
        char name[MAVLINK_MSG_NAMED_VALUE_FLOAT_FIELD_NAME_LEN + 1] = {};
        memcpy(name, nv.name, MAVLINK_MSG_NAMED_VALUE_FLOAT_FIELD_NAME_LEN);
        const QString key = _namedValueMap.value(QString::fromLatin1(name).trimmed());
        if (!key.isEmpty()) {
            if (key == QStringLiteral("rot.front")) {
                _setRpm(_rotorFrontIndex, nv.value);
            } else if (key == QStringLiteral("rot.rear")) {
                _setRpm(_rotorRearIndex, nv.value);
            } else {
                _set(key, nv.value);
            }
        }
        break;
    }
    default:
        break;
    }
}

void TandemTelemetry::_setRpm(int index, double rpm)
{
    if (index == _rotorFrontIndex) {
        _set(QStringLiteral("rot.front"), rpm);
    } else if (index == _rotorRearIndex) {
        _set(QStringLiteral("rot.rear"), rpm);
    }
}

void TandemTelemetry::_set(const QString &key, double value)
{
    if (qIsNaN(value) || qIsInf(value)) {
        return;
    }
    Sample &s = _samples[key];
    s.value = value;
    s.time  = _clock.elapsed();
}

/*---------------------------------------------------------------------------*/
/* Values                                                                    */
/*---------------------------------------------------------------------------*/

bool TandemTelemetry::_isFresh(const Sample &sample) const
{
    return (sample.time >= 0) && ((_clock.elapsed() - sample.time) <= _staleMs);
}

double TandemTelemetry::value(const QString &key) const
{
    const auto it = _samples.constFind(key);
    if ((it == _samples.constEnd()) || !_isFresh(it.value())) {
        return qQNaN();
    }
    return it.value().value;
}

bool TandemTelemetry::fresh(const QString &key) const
{
    const auto it = _samples.constFind(key);
    return (it != _samples.constEnd()) && _isFresh(it.value());
}

bool TandemTelemetry::seen(const QString &key) const
{
    const auto it = _samples.constFind(key);
    return (it != _samples.constEnd()) && (it.value().time >= 0);
}

void TandemTelemetry::_updateDerived()
{
    // Front/rear rotor speed split, as % of the faster rotor
    const double f = value(QStringLiteral("rot.front"));
    const double r = value(QStringLiteral("rot.rear"));
    if (!qIsNaN(f) && !qIsNaN(r)) {
        const double hi = qMax(f, r);
        if (hi >= _splitMinRpm) {
            _set(QStringLiteral("rot.split"), std::fabs(f - r) / hi * 100.0);
        }
    }

    // Remaining fuel endurance, minutes
    const double litres = value(QStringLiteral("fuel.L"));
    const double flow   = value(QStringLiteral("eng.flow"));
    if (!qIsNaN(litres) && !qIsNaN(flow) && (flow > 0.5)) {
        _set(QStringLiteral("fuel.endurance"), litres / flow * 60.0);
    }
}

int TandemTelemetry::_levelFor(const QString &key, double v) const
{
    if (qIsNaN(v)) {
        return NoData;
    }
    const QJsonArray zones = _items.value(key).toObject().value(QStringLiteral("zones")).toArray();
    if (zones.isEmpty()) {
        return Normal;
    }

    auto levelOf = [](const QString &name) {
        if (name == QStringLiteral("warning")) {
            return static_cast<int>(Warning);
        }
        if (name == QStringLiteral("caution")) {
            return static_cast<int>(Caution);
        }
        return static_cast<int>(Normal);
    };

    for (const QJsonValue &z : zones) {
        const QJsonArray zone = z.toArray();
        if (zone.size() < 3) {
            continue;
        }
        if ((v >= zone.at(0).toDouble()) && (v < zone.at(1).toDouble())) {
            return levelOf(zone.at(2).toString());
        }
    }
    // Outside every zone: use the nearest end
    const QJsonArray first = zones.first().toArray();
    const QJsonArray last  = zones.last().toArray();
    if ((first.size() >= 3) && (v < first.at(0).toDouble())) {
        return levelOf(first.at(2).toString());
    }
    return (last.size() >= 3) ? levelOf(last.at(2).toString()) : static_cast<int>(Normal);
}

int TandemTelemetry::level(const QString &key) const
{
    return _levelFor(key, value(key));
}

QVariantMap TandemTelemetry::spec(const QString &key) const
{
    return _items.value(key).toObject().toVariantMap();
}

/*---------------------------------------------------------------------------*/
/* Alerts                                                                    */
/*---------------------------------------------------------------------------*/

void TandemTelemetry::_resetForVehicle(Vehicle *vehicle)
{
    _vehicle = vehicle;
    _samples.clear();
    _alerts.clear();
    emit alertsChanged();
}

void TandemTelemetry::_tick()
{
    // Active vehicle switched (or disconnected): drop the previous vehicle's data
    Vehicle *active = MultiVehicleManager::instance()->activeVehicle();
    if (active != _vehicle.data()) {
        _resetForVehicle(active);
    }

    _updateDerived();

    _valuesMap.clear();
    _levelsMap.clear();
    _seenMap.clear();
    for (auto it = _samples.constBegin(); it != _samples.constEnd(); ++it) {
        if (it.value().time < 0) {
            continue;
        }
        _seenMap.insert(it.key(), true);
        if (_isFresh(it.value())) {
            _valuesMap.insert(it.key(), it.value().value);
            _levelsMap.insert(it.key(), _levelFor(it.key(), it.value().value));
        }
    }

    _evaluateAlerts();
    _revision++;
    emit revisionChanged();
}

void TandemTelemetry::_evaluateAlerts()
{
    struct Active {
        int     level = 0;
        QString text;
    };
    QHash<QString, Active> active;

    const bool armed  = _vehicle && _vehicle->armed();

    // Limit exceedances, as configured per item in tandem.json
    for (auto it = _items.constBegin(); it != _items.constEnd(); ++it) {
        const QJsonObject item = it.value().toObject();
        if (!item.value(QStringLiteral("alert")).toBool(false)) {
            continue;
        }
        if (item.value(QStringLiteral("alertWhenArmedOnly")).toBool(false) && !armed) {
            continue;
        }
        const int lvl = level(it.key());
        if (lvl == Warning) {
            active.insert(it.key(), Active{ lvl, item.value(QStringLiteral("warningText")).toString(item.value(QStringLiteral("label")).toString()) });
        } else if (lvl == Caution) {
            active.insert(it.key(), Active{ lvl, item.value(QStringLiteral("cautionText")).toString(item.value(QStringLiteral("label")).toString()) });
        }
    }

    // Data that was being received and has stopped while armed
    if (armed) {
        if (seen(QStringLiteral("eng.rpm")) && !fresh(QStringLiteral("eng.rpm"))) {
            active.insert(QStringLiteral("lost.engine"), Active{ static_cast<int>(Caution), _lostEngineText });
        }
        if ((seen(QStringLiteral("rot.front")) && !fresh(QStringLiteral("rot.front")))
                || (seen(QStringLiteral("rot.rear")) && !fresh(QStringLiteral("rot.rear")))) {
            active.insert(QStringLiteral("lost.rotor"), Active{ static_cast<int>(Caution), _lostRotorText });
        }
    }

    bool changed = false;
    const QString now = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"));

    // Drop cleared alerts
    for (int i = _alerts.count() - 1; i >= 0; i--) {
        if (!active.contains(_alerts[i].id)) {
            _alerts.removeAt(i);
            changed = true;
        }
    }
    // Add new / update existing
    for (auto it = active.constBegin(); it != active.constEnd(); ++it) {
        bool found = false;
        for (Alert &a : _alerts) {
            if (a.id == it.key()) {
                found = true;
                if (a.level != it.value().level) {
                    if (it.value().level > a.level) {
                        a.acked = false;    // escalation needs a fresh acknowledgement
                    }
                    a.level = it.value().level;
                    changed = true;
                }
                if (a.text != it.value().text) {
                    a.text = it.value().text;
                    changed = true;
                }
                break;
            }
        }
        if (!found) {
            Alert alert;
            alert.id    = it.key();
            alert.level = it.value().level;
            alert.text  = it.value().text;
            alert.time  = now;
            alert.acked = false;
            _alerts.append(alert);
            changed = true;
        }
    }

    if (changed) {
        std::stable_sort(_alerts.begin(), _alerts.end(), [](const Alert &a, const Alert &b) { return a.level > b.level; });
        emit alertsChanged();
    }
}

QVariantList TandemTelemetry::alerts() const
{
    QVariantList list;
    for (const Alert &a : _alerts) {
        QVariantMap m;
        m[QStringLiteral("id")]    = a.id;
        m[QStringLiteral("level")] = a.level;
        m[QStringLiteral("text")]  = a.text;
        m[QStringLiteral("time")]  = a.time;
        m[QStringLiteral("acked")] = a.acked;
        list.append(m);
    }
    return list;
}

void TandemTelemetry::acknowledgeAll()
{
    bool changed = false;
    for (Alert &a : _alerts) {
        if (!a.acked) {
            a.acked = true;
            changed = true;
        }
    }
    if (changed) {
        emit alertsChanged();
    }
}

bool TandemTelemetry::masterWarning() const
{
    return std::any_of(_alerts.cbegin(), _alerts.cend(), [](const Alert &a) { return (a.level == Warning) && !a.acked; });
}

bool TandemTelemetry::masterCaution() const
{
    return std::any_of(_alerts.cbegin(), _alerts.cend(), [](const Alert &a) { return (a.level == Caution) && !a.acked; });
}

bool TandemTelemetry::anyWarning() const
{
    return std::any_of(_alerts.cbegin(), _alerts.cend(), [](const Alert &a) { return a.level == Warning; });
}

bool TandemTelemetry::anyCaution() const
{
    return std::any_of(_alerts.cbegin(), _alerts.cend(), [](const Alert &a) { return a.level == Caution; });
}
