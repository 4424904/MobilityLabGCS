#include "MLDemo.h"

#include "LinkManager.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QLoggingCategory>
#include <QtCore/QStandardPaths>
#include <QtCore/QtMath>

#include <algorithm>
#include <cmath>
#include <cstring>

Q_LOGGING_CATEGORY(MLDemoLog, "MobilityLab.Demo")

namespace {
constexpr double kR = 6371000.0;
constexpr double kG = 9.81;
constexpr int kComp = MAV_COMP_ID_AUTOPILOT1;
constexpr int MAIN_MANUAL = 1, MAIN_ALTCTL = 2, MAIN_POSCTL = 3, MAIN_AUTO = 4, MAIN_ACRO = 5, MAIN_OFFBOARD = 6, MAIN_STAB = 7;
constexpr int AUTO_READY = 1, AUTO_TAKEOFF = 2, AUTO_LOITER = 3, AUTO_MISSION = 4, AUTO_RTL = 5, AUTO_LAND = 6;
// demo site (local east / north metres from here); same place as the CI SITL spawn points
constexpr double kLat0 = 37.2100856, kLon0 = 126.8307462;

struct NE { double n, e; };
NE toNe(double lat0, double lon0, double lat, double lon)
{
    return {qDegreesToRadians(lat - lat0) * kR, qDegreesToRadians(lon - lon0) * kR * std::cos(qDegreesToRadians(lat0))};
}
void fromNe(double lat0, double lon0, double n, double e, double &lat, double &lon)
{
    lat = lat0 + qRadiansToDegrees(n / kR);
    lon = lon0 + qRadiansToDegrees(e / (kR * std::cos(qDegreesToRadians(lat0))));
}
double clamp(double v, double lo, double hi) { return std::max(lo, std::min(hi, v)); }
bool isNavCmd(int c) { return c == MAV_CMD_NAV_WAYPOINT || c == MAV_CMD_NAV_TAKEOFF || c == MAV_CMD_NAV_LAND || c == MAV_CMD_NAV_LOITER_UNLIM
                              || c == MAV_CMD_NAV_LOITER_TIME || c == MAV_CMD_NAV_RETURN_TO_LAUNCH; }

// demo scenarios: homes and missions in local metres (east, north) from the site origin
struct DemoWp { int cmd; double e, n, alt; double hold; };
struct DemoVeh { double homeE, homeN; double cruise; std::vector<DemoWp> wps; };
std::vector<DemoVeh> scenarioDef(const QString &s)
{
    if (s == QLatin1String("single")) {
        return {{0, 0, 4.0, {{MAV_CMD_NAV_TAKEOFF, 0, 0, 15, 0}, {MAV_CMD_NAV_WAYPOINT, 0, 60, 15, 0}, {MAV_CMD_NAV_WAYPOINT, 50, 60, 15, 3},
                             {MAV_CMD_NAV_WAYPOINT, 50, 0, 20, 0}, {MAV_CMD_NAV_WAYPOINT, 25, -20, 20, 0}, {MAV_CMD_NAV_LAND, 0, 0, 0, 0}}}};
    }
    // duo: two vehicles on the same altitude whose tracks cross at 90° at the same time → ACACT avoidance
    std::vector<DemoVeh> v = {
        {0, 0, 3.0, {{MAV_CMD_NAV_TAKEOFF, 0, 0, 10, 0}, {MAV_CMD_NAV_WAYPOINT, -20, 40, 10, 0}, {MAV_CMD_NAV_WAYPOINT, 40, 100, 10, 0},
                     {MAV_CMD_NAV_WAYPOINT, 40, 125, 10, 0}, {MAV_CMD_NAV_LAND, 40, 130, 0, 0}}},
        {15, 0, 3.0, {{MAV_CMD_NAV_TAKEOFF, 15, 0, 10, 0}, {MAV_CMD_NAV_WAYPOINT, 40, 40, 10, 0}, {MAV_CMD_NAV_WAYPOINT, -20, 100, 10, 0},
                      {MAV_CMD_NAV_WAYPOINT, -20, 125, 10, 0}, {MAV_CMD_NAV_LAND, -20, 130, 0, 0}}},
    };
    if (s == QLatin1String("trio")) {
        // third vehicle crosses the same point 8 m higher: vertical separation, no avoidance needed
        v.push_back({30, 0, 3.0, {{MAV_CMD_NAV_TAKEOFF, 30, 0, 18, 0}, {MAV_CMD_NAV_WAYPOINT, 10, 40, 18, 0}, {MAV_CMD_NAV_WAYPOINT, 10, 100, 18, 0},
                                  {MAV_CMD_NAV_WAYPOINT, 10, 125, 18, 0}, {MAV_CMD_NAV_LAND, 10, 130, 0, 0}}});
    }
    return v;
}
}

// ============================================================================
// link
// ============================================================================
MLDemoLink::MLDemoLink(SharedLinkConfigurationPtr &config, MLDemo *demo)
    : LinkInterface(config)
    , _demo(demo)
{
    _inChan = LinkManager::instance()->allocateMavlinkChannel();
    _outChan = LinkManager::instance()->allocateMavlinkChannel();
}

MLDemoLink::~MLDemoLink()
{
    disconnect();
    if (_inChan != LinkManager::invalidMavlinkChannel()) {
        LinkManager::instance()->freeMavlinkChannel(_inChan);
    }
    if (_outChan != LinkManager::invalidMavlinkChannel()) {
        LinkManager::instance()->freeMavlinkChannel(_outChan);
    }
}

bool MLDemoLink::_connect()
{
    if (_inChan == LinkManager::invalidMavlinkChannel() || _outChan == LinkManager::invalidMavlinkChannel()) {
        return false;
    }
    _connected = true;
    QMetaObject::invokeMethod(this, [this]() { emit connected(); }, Qt::QueuedConnection);
    return true;
}

void MLDemoLink::disconnect()
{
    if (_connected) {
        _connected = false;
        emit disconnected();
    }
}

void MLDemoLink::_writeBytes(const QByteArray &bytes)
{
    if (!_connected || !_demo) {
        return;
    }
    emit bytesSent(this, bytes);
    _rxBytes += bytes.size();
    // Answer after this call returns (like a real link): the GCS registers what it waits for
    // (command acks, parameters) right after writing, so a reply inside the write would be missed.
    QMetaObject::invokeMethod(this, [this, bytes]() {
        if (!_connected || !_demo) {
            return;
        }
        mavlink_message_t msg;
        mavlink_status_t status;
        for (const char c : bytes) {
            const uint8_t r = mavlink_parse_char(_inChan, static_cast<uint8_t>(c), &msg, &status);
            if (r == MAVLINK_FRAMING_OK) {
                _rxMsgs++;
                _demo->receive(msg);
            } else if (r != MAVLINK_FRAMING_INCOMPLETE) {
                _rxBad++;
            }
        }
    }, Qt::QueuedConnection);
}

void MLDemoLink::deliver(const mavlink_message_t &msg)
{
    if (!_connected) {
        return;
    }
    uint8_t buf[MAVLINK_MAX_PACKET_LEN];
    const int len = mavlink_msg_to_send_buffer(buf, &msg);
    emit bytesReceived(this, QByteArray(reinterpret_cast<const char *>(buf), len));
}

// ============================================================================
// demo controller
// ============================================================================
MLDemo::MLDemo(QObject *parent)
    : QObject(parent)
{
    _instance = this;
    _timer.setInterval(20);
    connect(&_timer, &QTimer::timeout, this, &MLDemo::_step);
    LinkManager::setCustomLinkFactory([this](SharedLinkConfigurationPtr &cfg) -> SharedLinkInterfacePtr {
        if (dynamic_cast<MLDemoLinkConfiguration *>(cfg.get())) {
            return std::make_shared<MLDemoLink>(cfg, this);
        }
        return nullptr;
    });
}

MLDemo::~MLDemo()
{
    stop();
    LinkManager::setCustomLinkFactory(nullptr);
    if (_instance == this) {
        _instance = nullptr;
    }
}

QVariantList MLDemo::scenarios() const
{
    return {
        QVariantMap{{QStringLiteral("key"), QStringLiteral("single")}, {QStringLiteral("n"), 1},
                    {QStringLiteral("title"), tr("단일 기체 미션")}, {QStringLiteral("text"), tr("1기 · 사각 경로 미션 · 단일 기체 관제와 계기 시연")}},
        QVariantMap{{QStringLiteral("key"), QStringLiteral("duo")}, {QStringLiteral("n"), 2},
                    {QStringLiteral("title"), tr("교차 비행 · ACACT 회피")}, {QStringLiteral("text"), tr("2기 · 같은 고도에서 90° 교차 · 충돌 예측 → 회피 기동 → 미션 복귀")}},
        QVariantMap{{QStringLiteral("key"), QStringLiteral("trio")}, {QStringLiteral("n"), 3},
                    {QStringLiteral("title"), tr("3기 편대 · 고도 분리")}, {QStringLiteral("text"), tr("3기 · 2기 교차 회피 + 1기는 8 m 위에서 통과 (수직 분리)")}},
    };
}

void MLDemo::setTimeScale(double s)
{
    s = clamp(s, 0.5, 4.0);
    if (!qFuzzyCompare(s, _timeScale)) {
        _timeScale = s;
        emit timeScaleChanged();
    }
}

bool MLDemo::isDemoLink(const LinkInterface *link)
{
    return link && link->linkConfiguration() && dynamic_cast<const MLDemoLinkConfiguration *>(link->linkConfiguration().get());
}

bool MLDemo::isDemoSysid(int sysid) const
{
    if (!_active) {
        return false;
    }
    for (const MLDemoVehicle &v : _v) {
        if (v.sysid == sysid) {
            return true;
        }
    }
    return false;
}

MLDemoVehicle *MLDemo::_veh(int sysid)
{
    for (MLDemoVehicle &v : _v) {
        if (v.sysid == sysid) {
            return &v;
        }
    }
    return nullptr;
}

bool MLDemo::start(const QString &scenario)
{
    if (_active) {
        return false;
    }
    const std::vector<DemoVeh> def = scenarioDef(scenario);
    if (def.empty()) {
        return false;
    }
    if (_params.empty()) {
        _loadParams();
    }
    // 1) structural separation: from now on only the demo link may exist; close every real link
    LinkManager::setLinkGate([](const SharedLinkConfigurationPtr &cfg) { return dynamic_cast<MLDemoLinkConfiguration *>(cfg.get()) != nullptr; });
    LinkManager::instance()->disconnectAll();

    // 2) vehicles: on the ground at their homes, disarmed, missions on board (as if uploaded before)
    _v.clear();
    int id = 1;
    for (const DemoVeh &d : def) {
        MLDemoVehicle v;
        v.sysid = id;
        fromNe(kLat0, kLon0, d.homeN, d.homeE, v.homeLat, v.homeLon);
        v.lat = v.homeLat;
        v.lon = v.homeLon;
        v.yaw = 0;
        v.cruise = d.cruise;
        v.rtlAlt = 20.0 + 6.0 * (id - 1);
        v.batt = 100.0 - 3.0 * (id - 1);
        for (const DemoWp &w : d.wps) {
            MLDemoVehicle::Item it;
            it.cmd = w.cmd;
            it.frame = MAV_FRAME_GLOBAL_RELATIVE_ALT_INT;
            it.p[0] = static_cast<float>(w.hold);
            fromNe(kLat0, kLon0, w.n, w.e, it.x, it.y);
            it.z = static_cast<float>(w.alt);
            v.mission.push_back(it);
        }
        _v.push_back(v);
        id++;
    }
    _scenario = scenario;
    _writePlans(scenario);

    // 3) the demo link
    _config = std::make_shared<MLDemoLinkConfiguration>(QStringLiteral("MobilityLab Demo"));
    _config->setDynamic(true);
    _simTime = 0;
    _tickN = 0;
    _wall.start();
    _lastWall = 0;
    if (!LinkManager::instance()->createConnectedLink(_config)) {
        qCWarning(MLDemoLog) << "demo link could not be created";
        LinkManager::setLinkGate(nullptr);
        _v.clear();
        return false;
    }
    _active = true;
    _timer.start();
    qCInfo(MLDemoLog) << "demo started:" << scenario << _v.size() << "vehicles";
    emit activeChanged();
    emit notice(tr("데모 시작 — 실기체 링크 차단됨"));
    return true;
}

void MLDemo::stop()
{
    if (!_active) {
        return;
    }
    _timer.stop();
    if (_config && _config->link()) {
        LinkManager::instance()->disconnectLink(_config->link());
    }
    _config.reset();
    _v.clear();
    _active = false;
    _scenario.clear();
    LinkManager::setLinkGate(nullptr);   // real links (auto-connect) may connect again
    qCInfo(MLDemoLog) << "demo stopped";
    emit activeChanged();
    emit notice(tr("데모 종료 — 실기체 링크 허용"));
}

void MLDemo::setLinkCut(int sysid, bool cut)
{
    if (MLDemoVehicle *v = _veh(sysid)) {
        v->linkCut = cut;
        emit tick();
    }
}

QVariantList MLDemo::vehiclesV() const
{
    QVariantList out;
    for (const MLDemoVehicle &v : _v) {
        out.append(QVariantMap{{QStringLiteral("sysid"), v.sysid}, {QStringLiteral("linkCut"), v.linkCut},
                               {QStringLiteral("armed"), v.armed}, {QStringLiteral("inAir"), v.inAir}, {QStringLiteral("alt"), v.alt}});
    }
    return out;
}

void MLDemo::_writePlans(const QString &scenario)
{
    // the same missions as .plan files, so the operator can open / edit / upload them like any other plan
    _planDir = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath(QStringLiteral("MobilityLabDemo"));
    QDir().mkpath(_planDir);
    for (const MLDemoVehicle &v : _v) {
        QJsonArray items;
        int k = 1;
        for (const MLDemoVehicle::Item &it : v.mission) {
            QJsonArray params{it.p[0], 0, 0, QJsonValue(), it.x, it.y, it.z};
            items.append(QJsonObject{{QStringLiteral("type"), QStringLiteral("SimpleItem")}, {QStringLiteral("command"), it.cmd},
                                     {QStringLiteral("frame"), it.frame}, {QStringLiteral("autoContinue"), true}, {QStringLiteral("doJumpId"), k++},
                                     {QStringLiteral("params"), params}, {QStringLiteral("Altitude"), it.z}, {QStringLiteral("AltitudeMode"), 1},
                                     {QStringLiteral("AMSLAltAboveTerrain"), QJsonValue()}});
        }
        const QJsonObject mission{{QStringLiteral("version"), 2}, {QStringLiteral("firmwareType"), MAV_AUTOPILOT_PX4}, {QStringLiteral("vehicleType"), MAV_TYPE_QUADROTOR},
                                  {QStringLiteral("cruiseSpeed"), 15}, {QStringLiteral("hoverSpeed"), v.cruise}, {QStringLiteral("globalPlanAltitudeMode"), 1},
                                  {QStringLiteral("plannedHomePosition"), QJsonArray{v.homeLat, v.homeLon, 0}}, {QStringLiteral("items"), items}};
        const QJsonObject plan{{QStringLiteral("fileType"), QStringLiteral("Plan")}, {QStringLiteral("groundStation"), QStringLiteral("MobilityLab GCS (demo)")},
                               {QStringLiteral("version"), 1}, {QStringLiteral("mission"), mission},
                               {QStringLiteral("geoFence"), QJsonObject{{QStringLiteral("version"), 2}, {QStringLiteral("circles"), QJsonArray()}, {QStringLiteral("polygons"), QJsonArray()}}},
                               {QStringLiteral("rallyPoints"), QJsonObject{{QStringLiteral("version"), 2}, {QStringLiteral("points"), QJsonArray()}}}};
        QFile f(QDir(_planDir).filePath(QStringLiteral("DEMO_%1_D%2.plan").arg(scenario).arg(v.sysid)));
        if (f.open(QIODevice::WriteOnly)) {
            f.write(QJsonDocument(plan).toJson());
        }
    }
}

// ---------------------------------------------------------------------------
// parameters: PX4 defaults from QGC's PX4 parameter metadata, with the values a configured
// PX4 multicopter (and the CI SITL vehicles) have
// ---------------------------------------------------------------------------
void MLDemo::_loadParams()
{
    QFile f(QStringLiteral(":/FirmwarePlugin/PX4/PX4ParameterFactMetaData.json"));
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonArray a = QJsonDocument::fromJson(f.readAll()).object().value(QStringLiteral("parameters")).toArray();
        for (const QJsonValue &v : a) {
            const QJsonObject o = v.toObject();
            const QString name = o.value(QStringLiteral("name")).toString();
            if (name.isEmpty() || name.size() > 16 || name.contains(QLatin1Char('$'))) {
                continue;
            }
            const QString t = o.value(QStringLiteral("type")).toString();
            const int type = t.compare(QLatin1String("Float"), Qt::CaseInsensitive) == 0 ? MAV_PARAM_TYPE_REAL32 : MAV_PARAM_TYPE_INT32;
            _params.push_back({name, type, o.value(QStringLiteral("default")).toDouble()});
        }
    }
    const QHash<QString, double> set = {
        {QStringLiteral("SYS_AUTOSTART"), 4001}, {QStringLiteral("CAL_ACC0_ID"), 1310988}, {QStringLiteral("CAL_GYRO0_ID"), 1310988},
        {QStringLiteral("CAL_MAG0_ID"), 197388}, {QStringLiteral("CAL_BARO0_ID"), 6620172}, {QStringLiteral("BAT1_N_CELLS"), 4},
        {QStringLiteral("COM_RC_IN_MODE"), 4}, {QStringLiteral("COM_OF_LOSS_T"), 1.0}, {QStringLiteral("COM_OBL_RC_ACT"), 5},
        {QStringLiteral("NAV_DLL_ACT"), 0}, {QStringLiteral("NAV_RCL_ACT"), 0}, {QStringLiteral("NAV_ACC_RAD"), 2.0},
        {QStringLiteral("MIS_TAKEOFF_ALT"), 8.0}, {QStringLiteral("MPC_XY_CRUISE"), 3.0}, {QStringLiteral("MPC_TKO_SPEED"), 1.0},
        {QStringLiteral("RTL_CONE_ANG"), 0}, {QStringLiteral("RC_MAP_ROLL"), 1}, {QStringLiteral("RC_MAP_PITCH"), 2},
        {QStringLiteral("RC_MAP_THROTTLE"), 3}, {QStringLiteral("RC_MAP_YAW"), 4},
    };
    bool hasSysId = false;
    for (Param &p : _params) {
        auto it = set.find(p.name);
        if (it != set.end()) {
            p.value = it.value();
        }
        hasSysId = hasSysId || p.name == QLatin1String("MAV_SYS_ID");
    }
    if (!hasSysId) {
        _params.push_back({QStringLiteral("MAV_SYS_ID"), MAV_PARAM_TYPE_INT32, 1});
    }
}

void MLDemo::_sendParam(MLDemoVehicle &v, int index)
{
    if (index < 0 || index >= static_cast<int>(_params.size())) {
        return;
    }
    const Param &p = _params[index];
    double value = p.value;
    if (p.name == QLatin1String("MAV_SYS_ID")) {
        value = v.sysid;
    } else if (p.name == QLatin1String("RTL_RETURN_ALT")) {
        value = v.rtlAlt;
    }
    if (v.paramOverride.contains(p.name)) {
        value = v.paramOverride.value(p.name);
    }
    mavlink_param_value_t pv{};
    mavlink_param_union_t u{};
    if (p.type == MAV_PARAM_TYPE_REAL32) {
        u.param_float = static_cast<float>(value);
    } else {
        u.param_int32 = static_cast<int32_t>(std::lround(value));   // PX4: integers byte-wise in the float field
    }
    pv.param_value = u.param_float;
    pv.param_type = static_cast<uint8_t>(p.type);
    pv.param_count = static_cast<uint16_t>(_params.size());
    pv.param_index = static_cast<uint16_t>(index);
    std::strncpy(pv.param_id, p.name.toLatin1().constData(), sizeof(pv.param_id));
    mavlink_message_t m;
    mavlink_msg_param_value_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &pv);
    _send(v, m);
}

void MLDemo::_param(MLDemoVehicle &v, const mavlink_message_t &msg)
{
    switch (msg.msgid) {
    case MAVLINK_MSG_ID_PARAM_REQUEST_LIST:
        v.paramIdx = 0;   // streamed from _step (100 per tick)
        break;
    case MAVLINK_MSG_ID_PARAM_REQUEST_READ: {
        mavlink_param_request_read_t r;
        mavlink_msg_param_request_read_decode(&msg, &r);
        if (r.param_index >= 0) {
            _sendParam(v, r.param_index);
        } else {
            const QString name = QString::fromLatin1(r.param_id, static_cast<int>(strnlen(r.param_id, sizeof(r.param_id))));
            for (int i = 0; i < static_cast<int>(_params.size()); i++) {
                if (_params[i].name == name) {
                    _sendParam(v, i);
                    break;
                }
            }
        }
        break;
    }
    case MAVLINK_MSG_ID_PARAM_SET: {
        mavlink_param_set_t r;
        mavlink_msg_param_set_decode(&msg, &r);
        const QString name = QString::fromLatin1(r.param_id, static_cast<int>(strnlen(r.param_id, sizeof(r.param_id))));
        mavlink_param_union_t u{};
        u.param_float = r.param_value;
        for (int i = 0; i < static_cast<int>(_params.size()); i++) {
            if (_params[i].name == name) {
                v.paramOverride[name] = _params[i].type == MAV_PARAM_TYPE_REAL32 ? static_cast<double>(u.param_float) : static_cast<double>(u.param_int32);
                if (name == QLatin1String("MPC_XY_CRUISE")) {
                    v.cruise = v.paramOverride[name];
                } else if (name == QLatin1String("RTL_RETURN_ALT")) {
                    v.rtlAlt = v.paramOverride[name];
                }
                _sendParam(v, i);
                break;
            }
        }
        break;
    }
    default:
        break;
    }
}

// ---------------------------------------------------------------------------
// GCS → vehicles
// ---------------------------------------------------------------------------
void MLDemo::receive(const mavlink_message_t &msg)
{
    // target system: most messages carry one; route to that vehicle (0 = all)
    int target = -1;
    switch (msg.msgid) {
    case MAVLINK_MSG_ID_COMMAND_LONG: target = mavlink_msg_command_long_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_COMMAND_INT: target = mavlink_msg_command_int_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_PARAM_REQUEST_LIST: target = mavlink_msg_param_request_list_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_PARAM_REQUEST_READ: target = mavlink_msg_param_request_read_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_PARAM_SET: target = mavlink_msg_param_set_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_MISSION_REQUEST_LIST: target = mavlink_msg_mission_request_list_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_MISSION_REQUEST_INT: target = mavlink_msg_mission_request_int_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_MISSION_REQUEST: target = mavlink_msg_mission_request_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_MISSION_COUNT: target = mavlink_msg_mission_count_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_MISSION_ITEM_INT: target = mavlink_msg_mission_item_int_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_MISSION_CLEAR_ALL: target = mavlink_msg_mission_clear_all_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_MISSION_SET_CURRENT: target = mavlink_msg_mission_set_current_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_SET_POSITION_TARGET_LOCAL_NED: target = mavlink_msg_set_position_target_local_ned_get_target_system(&msg); break;
    case MAVLINK_MSG_ID_SET_MODE: target = mavlink_msg_set_mode_get_target_system(&msg); break;
    default: return;   // heartbeats, timesync, … — nothing to do
    }
    for (MLDemoVehicle &v : _v) {
        if (target != 0 && target != v.sysid) {
            continue;
        }
        if (v.linkCut) {
            continue;   // simulated link loss: the vehicle hears nothing
        }
        switch (msg.msgid) {
        case MAVLINK_MSG_ID_COMMAND_LONG: {
            mavlink_command_long_t c;
            mavlink_msg_command_long_decode(&msg, &c);
            const float p[7] = {c.param1, c.param2, c.param3, c.param4, c.param5, c.param6, c.param7};
            _command(v, c.command, p, c.param5, c.param6, MAV_FRAME_GLOBAL, msg.sysid, msg.compid);
            break;
        }
        case MAVLINK_MSG_ID_COMMAND_INT: {
            mavlink_command_int_t c;
            mavlink_msg_command_int_decode(&msg, &c);
            const float p[7] = {c.param1, c.param2, c.param3, c.param4, static_cast<float>(c.x * 1e-7), static_cast<float>(c.y * 1e-7), c.z};
            _command(v, c.command, p, c.x == INT32_MAX ? qQNaN() : c.x * 1e-7, c.y == INT32_MAX ? qQNaN() : c.y * 1e-7, c.frame, msg.sysid, msg.compid);
            break;
        }
        case MAVLINK_MSG_ID_SET_MODE: {
            const uint32_t cm = mavlink_msg_set_mode_get_custom_mode(&msg);
            _setMode(v, (cm >> 16) & 0xFF, (cm >> 24) & 0xFF);
            break;
        }
        case MAVLINK_MSG_ID_SET_POSITION_TARGET_LOCAL_NED: {
            mavlink_set_position_target_local_ned_t s;
            mavlink_msg_set_position_target_local_ned_decode(&msg, &s);
            // velocity setpoint (position ignored): the way the ACACT guard flies an avoidance
            if (!std::isnan(s.vx) && !std::isnan(s.vy)) {
                v.spN = s.vx;
                v.spE = s.vy;
                v.spD = std::isnan(s.vz) ? 0.0 : s.vz;
                v.spT = _now();
            }
            break;
        }
        case MAVLINK_MSG_ID_PARAM_REQUEST_LIST:
        case MAVLINK_MSG_ID_PARAM_REQUEST_READ:
        case MAVLINK_MSG_ID_PARAM_SET:
            _param(v, msg);
            break;
        default:
            _mission(v, msg);
            break;
        }
    }
}

void MLDemo::_ack(MLDemoVehicle &v, int cmd, int result, int sysid, int compid)
{
    mavlink_command_ack_t a{};
    a.command = static_cast<uint16_t>(cmd);
    a.result = static_cast<uint8_t>(result);
    a.target_system = static_cast<uint8_t>(sysid);
    a.target_component = static_cast<uint8_t>(compid);
    mavlink_message_t m;
    mavlink_msg_command_ack_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &a);
    _send(v, m);
}

void MLDemo::_sendText(MLDemoVehicle &v, int severity, const QString &text)
{
    mavlink_statustext_t t{};
    t.severity = static_cast<uint8_t>(severity);
    std::strncpy(t.text, text.toUtf8().constData(), sizeof(t.text));
    mavlink_message_t m;
    mavlink_msg_statustext_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &t);
    _send(v, m);
}

void MLDemo::_setMode(MLDemoVehicle &v, int main, int sub)
{
    if (main == MAIN_AUTO && sub == AUTO_LOITER) {
        v.loiterSet = false;   // hold where it is now
    }
    if (main == MAIN_AUTO && sub == AUTO_MISSION && v.cur >= static_cast<int>(v.mission.size())) {
        v.cur = 0;
    }
    v.main = main;
    v.sub = (main == MAIN_AUTO) ? sub : 0;
    _sendHeartbeat(v);   // report the new mode at once (like PX4's immediate heartbeat on mode change)
}

void MLDemo::_command(MLDemoVehicle &v, int cmd, const float p[7], double x, double y, int frame, int sysid, int compid)
{
    Q_UNUSED(frame)
    switch (cmd) {
    case MAV_CMD_COMPONENT_ARM_DISARM:
        if (p[0] > 0.5f) {
            if (v.armed) {
                _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
            } else if (v.batt < 15) {
                _sendText(v, MAV_SEVERITY_CRITICAL, QStringLiteral("Arming denied: low battery"));
                _ack(v, cmd, MAV_RESULT_DENIED, sysid, compid);
            } else {
                v.armed = true;
                v.landedAt = _now();
                _sendText(v, MAV_SEVERITY_INFO, QStringLiteral("Armed by external command"));
                _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
                _sendHeartbeat(v);
            }
        } else {
            if (v.inAir && std::lround(p[1]) != 21196) {
                _ack(v, cmd, MAV_RESULT_DENIED, sysid, compid);
            } else {
                v.armed = false;
                v.inAir = false;
                v.alt = 0;
                v.vn = v.ve = v.vd = 0;
                _sendText(v, MAV_SEVERITY_INFO, QStringLiteral("Disarmed by external command"));
                _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
                _sendHeartbeat(v);
            }
        }
        return;
    case MAV_CMD_NAV_TAKEOFF: {
        if (!v.armed) {
            _ack(v, cmd, MAV_RESULT_DENIED, sysid, compid);
            return;
        }
        const double amsl = p[6];
        v.takeoffAlt = std::isnan(amsl) ? 8.0 : clamp(amsl - v.homeAmsl, 2.0, 120.0);
        _setMode(v, MAIN_AUTO, AUTO_TAKEOFF);
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    }
    case MAV_CMD_DO_SET_MODE: {
        const int main = static_cast<int>(std::lround(p[1]));
        const int sub = static_cast<int>(std::lround(p[2]));
        if (main == MAIN_OFFBOARD && _now() - v.spT > 0.5) {
            _sendText(v, MAV_SEVERITY_CRITICAL, QStringLiteral("Switching to Offboard is currently not available"));
            _ack(v, cmd, MAV_RESULT_TEMPORARILY_REJECTED, sysid, compid);
            return;
        }
        if (main == MAIN_AUTO && sub == AUTO_MISSION && v.mission.empty()) {
            _sendText(v, MAV_SEVERITY_CRITICAL, QStringLiteral("Mission rejected: no mission"));
            _ack(v, cmd, MAV_RESULT_DENIED, sysid, compid);
            return;
        }
        _setMode(v, main, sub);
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    }
    case MAV_CMD_MISSION_START:
        if (v.mission.empty()) {
            _ack(v, cmd, MAV_RESULT_DENIED, sysid, compid);
            return;
        }
        if (p[0] > 0) {
            _goToItem(v, static_cast<int>(p[0]));
        }
        _setMode(v, MAIN_AUTO, AUTO_MISSION);
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    case MAV_CMD_NAV_RETURN_TO_LAUNCH:
        _setMode(v, MAIN_AUTO, AUTO_RTL);
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    case MAV_CMD_NAV_LAND:
        _setMode(v, MAIN_AUTO, AUTO_LAND);
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    case MAV_CMD_DO_REPOSITION: {
        if (!v.inAir) {
            _ack(v, cmd, MAV_RESULT_DENIED, sysid, compid);
            return;
        }
        v.loiterLat = std::isnan(x) || x == 0 ? v.lat : x;
        v.loiterLon = std::isnan(y) || y == 0 ? v.lon : y;
        v.loiterAlt = std::isnan(p[6]) ? v.alt : clamp(p[6] - v.homeAmsl, 2.0, 120.0);
        v.main = MAIN_AUTO;
        v.sub = AUTO_LOITER;
        v.loiterSet = true;
        if (p[0] > 0) {
            v.cruise = p[0];
        }
        _sendHeartbeat(v);
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    }
    case MAV_CMD_DO_CHANGE_SPEED:
        if (p[1] > 0) {
            v.cruise = clamp(p[1], 0.5, 12.0);
        }
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    case MAV_CMD_DO_SET_MISSION_CURRENT:
        _goToItem(v, static_cast<int>(p[0]));
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    case MAV_CMD_CONDITION_YAW:
        v.yaw = qDegreesToRadians(static_cast<double>(p[0]));
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    case MAV_CMD_REQUEST_MESSAGE:
    case MAV_CMD_REQUEST_AUTOPILOT_CAPABILITIES: {
        const int id = cmd == MAV_CMD_REQUEST_AUTOPILOT_CAPABILITIES ? MAVLINK_MSG_ID_AUTOPILOT_VERSION : static_cast<int>(std::lround(p[0]));
        if (id == MAVLINK_MSG_ID_AUTOPILOT_VERSION) {
            _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
            mavlink_autopilot_version_t av{};
            av.capabilities = MAV_PROTOCOL_CAPABILITY_MAVLINK2 | MAV_PROTOCOL_CAPABILITY_MISSION_INT | MAV_PROTOCOL_CAPABILITY_COMMAND_INT
                              | MAV_PROTOCOL_CAPABILITY_MISSION_FENCE | MAV_PROTOCOL_CAPABILITY_MISSION_RALLY | MAV_PROTOCOL_CAPABILITY_PARAM_ENCODE_BYTEWISE
                              | MAV_PROTOCOL_CAPABILITY_SET_POSITION_TARGET_LOCAL_NED;
            av.flight_sw_version = (1u << 24) | (16u << 16) | (2u << 8) | 255u;   // PX4 v1.16.2 official
            av.vendor_id = 0x26AC;
            av.product_id = 0x0011;
            av.uid = 0x4D4C44454D4F0000ull + static_cast<uint64_t>(v.sysid);   // "MLDEMO" + id
            mavlink_message_t m;
            mavlink_msg_autopilot_version_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &av);
            _send(v, m);
        } else if (id == MAVLINK_MSG_ID_HOME_POSITION) {
            _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
            _sendTelemetry(v, false, true);
        } else if (id == MAVLINK_MSG_ID_GLOBAL_POSITION_INT || id == MAVLINK_MSG_ID_EXTENDED_SYS_STATE || id == MAVLINK_MSG_ID_BATTERY_STATUS
                   || id == MAVLINK_MSG_ID_SYS_STATUS || id == MAVLINK_MSG_ID_GPS_RAW_INT) {
            _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        } else {
            _ack(v, cmd, MAV_RESULT_UNSUPPORTED, sysid, compid);
        }
        return;
    }
    case MAV_CMD_SET_MESSAGE_INTERVAL:
        _ack(v, cmd, MAV_RESULT_ACCEPTED, sysid, compid);
        return;
    default:
        _ack(v, cmd, MAV_RESULT_UNSUPPORTED, sysid, compid);
        return;
    }
}

// ---------------------------------------------------------------------------
// mission protocol (vehicle side)
// ---------------------------------------------------------------------------
void MLDemo::_goToItem(MLDemoVehicle &v, int seq)
{
    v.cur = std::max(0, std::min(seq, static_cast<int>(v.mission.size())));
    v.holdUntil = -1;
    mavlink_mission_current_t c{};
    c.seq = static_cast<uint16_t>(v.cur);
    c.total = static_cast<uint16_t>(v.mission.size());
    c.mission_state = v.cur >= static_cast<int>(v.mission.size()) ? MISSION_STATE_COMPLETE : MISSION_STATE_ACTIVE;
    mavlink_message_t m;
    mavlink_msg_mission_current_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &c);
    _send(v, m);
}

void MLDemo::_mission(MLDemoVehicle &v, const mavlink_message_t &msg)
{
    auto sendCount = [&](int type, int count) {
        mavlink_mission_count_t c{};
        c.target_system = msg.sysid;
        c.target_component = msg.compid;
        c.count = static_cast<uint16_t>(count);
        c.mission_type = static_cast<uint8_t>(type);
        mavlink_message_t m;
        mavlink_msg_mission_count_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &c);
        _send(v, m);
    };
    auto sendAck = [&](int type, int result) {
        mavlink_mission_ack_t a{};
        a.target_system = msg.sysid;
        a.target_component = msg.compid;
        a.type = static_cast<uint8_t>(result);
        a.mission_type = static_cast<uint8_t>(type);
        mavlink_message_t m;
        mavlink_msg_mission_ack_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &a);
        _send(v, m);
    };
    auto request = [&](int type, int seq) {
        mavlink_mission_request_int_t r{};
        r.target_system = msg.sysid;
        r.target_component = msg.compid;
        r.seq = static_cast<uint16_t>(seq);
        r.mission_type = static_cast<uint8_t>(type);
        mavlink_message_t m;
        mavlink_msg_mission_request_int_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &r);
        _send(v, m);
    };
    switch (msg.msgid) {
    case MAVLINK_MSG_ID_MISSION_REQUEST_LIST: {
        const int type = mavlink_msg_mission_request_list_get_mission_type(&msg);
        sendCount(type, type == MAV_MISSION_TYPE_MISSION ? static_cast<int>(v.mission.size()) : 0);
        break;
    }
    case MAVLINK_MSG_ID_MISSION_REQUEST_INT:
    case MAVLINK_MSG_ID_MISSION_REQUEST: {
        const int seq = msg.msgid == MAVLINK_MSG_ID_MISSION_REQUEST_INT ? mavlink_msg_mission_request_int_get_seq(&msg) : mavlink_msg_mission_request_get_seq(&msg);
        const int type = msg.msgid == MAVLINK_MSG_ID_MISSION_REQUEST_INT ? mavlink_msg_mission_request_int_get_mission_type(&msg) : mavlink_msg_mission_request_get_mission_type(&msg);
        if (type != MAV_MISSION_TYPE_MISSION || seq < 0 || seq >= static_cast<int>(v.mission.size())) {
            sendAck(type, MAV_MISSION_INVALID_SEQUENCE);
            break;
        }
        const MLDemoVehicle::Item &it = v.mission[seq];
        mavlink_mission_item_int_t mi{};
        mi.target_system = msg.sysid;
        mi.target_component = msg.compid;
        mi.seq = static_cast<uint16_t>(seq);
        mi.frame = static_cast<uint8_t>(it.frame);
        mi.command = static_cast<uint16_t>(it.cmd);
        mi.current = seq == v.cur ? 1 : 0;
        mi.autocontinue = it.autoContinue ? 1 : 0;
        mi.param1 = it.p[0];
        mi.param2 = it.p[1];
        mi.param3 = it.p[2];
        mi.param4 = it.p[3];
        mi.x = static_cast<int32_t>(std::lround(it.x * 1e7));
        mi.y = static_cast<int32_t>(std::lround(it.y * 1e7));
        mi.z = it.z;
        mi.mission_type = MAV_MISSION_TYPE_MISSION;
        mavlink_message_t m;
        mavlink_msg_mission_item_int_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &mi);
        _send(v, m);
        break;
    }
    case MAVLINK_MSG_ID_MISSION_COUNT: {
        mavlink_mission_count_t c;
        mavlink_msg_mission_count_decode(&msg, &c);
        v.upType = c.mission_type;
        v.upCount = c.count;
        v.upNext = 0;
        v.upItems.clear();
        v.upT = _now();
        if (c.count == 0) {
            if (c.mission_type == MAV_MISSION_TYPE_MISSION) {
                v.mission.clear();
                _goToItem(v, 0);
            }
            v.upCount = -1;
            sendAck(c.mission_type, MAV_MISSION_ACCEPTED);
        } else {
            request(c.mission_type, 0);
        }
        break;
    }
    case MAVLINK_MSG_ID_MISSION_ITEM_INT: {
        mavlink_mission_item_int_t mi;
        mavlink_msg_mission_item_int_decode(&msg, &mi);
        if (v.upCount < 0 || mi.seq != v.upNext) {
            break;   // duplicate / out of order: the GCS retries
        }
        MLDemoVehicle::Item it;
        it.cmd = mi.command;
        it.frame = mi.frame;
        it.p[0] = mi.param1;
        it.p[1] = mi.param2;
        it.p[2] = mi.param3;
        it.p[3] = mi.param4;
        it.x = mi.x * 1e-7;
        it.y = mi.y * 1e-7;
        it.z = mi.z;
        it.autoContinue = mi.autocontinue != 0;
        v.upItems.push_back(it);
        v.upNext++;
        if (v.upNext < v.upCount) {
            request(v.upType, v.upNext);
        } else {
            if (v.upType == MAV_MISSION_TYPE_MISSION) {
                if (v.main == MAIN_AUTO && v.sub == AUTO_MISSION && v.inAir) {
                    // PX4: a new mission while flying one → hold until told to continue
                    _setMode(v, MAIN_AUTO, AUTO_LOITER);
                }
                v.mission = v.upItems;
                _goToItem(v, 0);
            }
            v.upCount = -1;
            sendAck(v.upType, MAV_MISSION_ACCEPTED);
        }
        break;
    }
    case MAVLINK_MSG_ID_MISSION_CLEAR_ALL: {
        const int type = mavlink_msg_mission_clear_all_get_mission_type(&msg);
        if (type == MAV_MISSION_TYPE_MISSION || type == MAV_MISSION_TYPE_ALL) {
            v.mission.clear();
            _goToItem(v, 0);
        }
        sendAck(type, MAV_MISSION_ACCEPTED);
        break;
    }
    case MAVLINK_MSG_ID_MISSION_SET_CURRENT:
        _goToItem(v, mavlink_msg_mission_set_current_get_seq(&msg));
        break;
    default:
        break;
    }
}

// ---------------------------------------------------------------------------
// simulation
// ---------------------------------------------------------------------------
void MLDemo::_step()
{
    const qint64 w = _wall.elapsed();
    double dt = (w - _lastWall) / 1000.0;
    _lastWall = w;
    dt = clamp(dt, 0.0, 0.1) * _timeScale;
    _simTime += dt;
    _tickN++;
    const bool fast = _tickN % 5 == 0;     // 10 Hz at 1×
    const bool slow = _tickN % 50 == 0;    // 1 Hz
    for (MLDemoVehicle &v : _v) {
        _stepVehicle(v, dt);
        if (v.paramIdx >= 0) {
            for (int i = 0; i < 100 && v.paramIdx < static_cast<int>(_params.size()); i++) {
                _sendParam(v, v.paramIdx++);
            }
            if (v.paramIdx >= static_cast<int>(_params.size())) {
                v.paramIdx = -1;
            }
        }
        if (fast || slow) {
            _sendTelemetry(v, fast, slow);
        }
        if (_tickN % 25 == 0) {
            _sendHeartbeat(v);   // 2 Hz
        }
    }
    if (slow) {
        emit tick();
        if (_tickN % 250 == 0) {
            auto *link = _config ? qobject_cast<MLDemoLink *>(_config->link()) : nullptr;
            if (link) {
                qCInfo(MLDemoLog) << "demo link rx bytes" << link->rxBytes() << "msgs" << link->rxMsgs() << "bad" << link->rxBad();
            }
        }
    }
}

void MLDemo::_stepVehicle(MLDemoVehicle &v, double dt)
{
    if (dt <= 0) {
        return;
    }
    const double t = _now();
    const NE here = toNe(kLat0, kLon0, v.lat, v.lon);
    double wantN = 0, wantE = 0, wantD = 0;     // desired velocity
    bool hold = true;

    auto goTo = [&](double lat, double lon, double alt, double speed) -> double {
        const NE tgt = toNe(kLat0, kLon0, lat, lon);
        const double dn = tgt.n - here.n, de = tgt.e - here.e;
        const double d = std::hypot(dn, de);
        const double sp = std::min({speed, std::sqrt(2.0 * 2.0 * d), 0.9 * d + 0.05});
        if (d > 0.05) {
            wantN = dn / d * sp;
            wantE = de / d * sp;
        }
        wantD = -clamp((alt - v.alt) * 0.8, -1.0, 2.0);
        hold = false;
        return d;
    };

    if (!v.armed) {
        v.vn = v.ve = v.vd = 0;
        v.inAir = false;
        v.alt = 0;
        v.roll = v.pitch = 0;
    } else {
        // auto-disarm on the ground (PX4 COM_DISARM_PRFLT)
        if (!v.inAir && v.landedAt >= 0 && t - v.landedAt > 15.0
            && !(v.main == MAIN_AUTO && (v.sub == AUTO_TAKEOFF || v.sub == AUTO_MISSION)) && v.main != MAIN_OFFBOARD) {
            v.armed = false;
            _sendText(v, MAV_SEVERITY_INFO, QStringLiteral("Disarmed by auto preflight disarming"));
            _sendHeartbeat(v);
            return;
        }
        // offboard loss failsafe (COM_OF_LOSS_T 1 s → COM_OBL_RC_ACT 5: Hold)
        if (v.main == MAIN_OFFBOARD && t - v.spT > 1.0) {
            _sendText(v, MAV_SEVERITY_CRITICAL, QStringLiteral("Failsafe activated: offboard control signal lost — Hold"));
            _setMode(v, MAIN_AUTO, AUTO_LOITER);
        }
        if (v.main == MAIN_OFFBOARD) {
            wantN = v.spN;
            wantE = v.spE;
            wantD = v.spD;
            hold = false;
            if (!v.inAir && wantD < -0.1) {
                v.inAir = true;
            }
        } else if (v.main == MAIN_AUTO) {
            switch (v.sub) {
            case AUTO_TAKEOFF:
                v.inAir = true;
                goTo(v.lat, v.lon, v.takeoffAlt, 0);
                wantD = -clamp((v.takeoffAlt - v.alt) * 0.8, -1.0, 1.0);
                if (std::fabs(v.takeoffAlt - v.alt) < 0.3) {
                    _setMode(v, MAIN_AUTO, AUTO_LOITER);
                }
                break;
            case AUTO_MISSION: {
                if (v.cur >= static_cast<int>(v.mission.size())) {
                    _setMode(v, MAIN_AUTO, AUTO_LOITER);
                    break;
                }
                const MLDemoVehicle::Item &it = v.mission[v.cur];
                auto advance = [&]() {
                    if (isNavCmd(it.cmd)) {
                        mavlink_mission_item_reached_t r{static_cast<uint16_t>(v.cur)};
                        mavlink_message_t m;
                        mavlink_msg_mission_item_reached_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &r);
                        _send(v, m);
                    }
                    _goToItem(v, v.cur + 1);
                };
                if (it.cmd == MAV_CMD_DO_CHANGE_SPEED) {
                    if (it.p[1] > 0) {
                        v.cruise = it.p[1];
                    }
                    advance();
                    break;
                }
                if (it.cmd == MAV_CMD_NAV_TAKEOFF) {
                    v.inAir = true;
                    goTo(v.lat, v.lon, it.z, 0);
                    wantD = -clamp((it.z - v.alt) * 0.8, -1.0, 1.0);
                    if (std::fabs(it.z - v.alt) < 0.4) {
                        advance();
                    }
                    break;
                }
                if (it.cmd == MAV_CMD_NAV_RETURN_TO_LAUNCH) {
                    _setMode(v, MAIN_AUTO, AUTO_RTL);
                    break;
                }
                if (!v.inAir) {
                    // mission started on the ground without a takeoff item: PX4 takes off to MIS_TAKEOFF_ALT first
                    v.inAir = true;
                }
                if (it.cmd == MAV_CMD_NAV_LAND) {
                    const double d = (it.x != 0 || it.y != 0) ? goTo(it.x, it.y, v.alt, v.cruise) : 0.0;
                    if (d < 1.0) {
                        wantN = wantE = 0;
                        wantD = 0.8;
                        hold = false;
                    }
                    break;
                }
                if (isNavCmd(it.cmd)) {
                    const double d = goTo(it.x, it.y, it.z, v.cruise);
                    if (d < 2.0 && std::fabs(it.z - v.alt) < 1.0) {
                        if (v.holdUntil < 0) {
                            v.holdUntil = t + it.p[0];
                        }
                        if (t >= v.holdUntil && it.cmd != MAV_CMD_NAV_LOITER_UNLIM) {
                            advance();
                        }
                    }
                } else {
                    advance();   // other DO / condition items: nothing to simulate
                }
                break;
            }
            case AUTO_RTL: {
                const double climbTo = std::max(v.alt, v.rtlAlt);
                const NE home = toNe(kLat0, kLon0, v.homeLat, v.homeLon);
                const double dHome = std::hypot(home.n - here.n, home.e - here.e);
                if (dHome > 1.5) {
                    if (v.alt < v.rtlAlt - 0.5 && dHome > 5) {
                        goTo(v.lat, v.lon, climbTo, 0);
                    } else {
                        goTo(v.homeLat, v.homeLon, climbTo, std::max(v.cruise, 5.0));
                    }
                } else {
                    goTo(v.homeLat, v.homeLon, v.alt, 1.0);
                    wantD = 0.8;
                }
                break;
            }
            case AUTO_LAND:
                goTo(v.lat, v.lon, v.alt, 0);
                wantN = wantE = 0;
                wantD = 0.8;
                break;
            case AUTO_LOITER:
            default:
                if (!v.loiterSet) {
                    v.loiterLat = v.lat;
                    v.loiterLon = v.lon;
                    v.loiterAlt = v.alt;
                    v.loiterSet = true;
                }
                if (v.inAir) {
                    goTo(v.loiterLat, v.loiterLon, v.loiterAlt, v.cruise);
                }
                break;
            }
        } else {
            // operator modes (position / altitude / manual …) without stick input: the aircraft holds
            if (!v.loiterSet) {
                v.loiterLat = v.lat;
                v.loiterLon = v.lon;
                v.loiterAlt = v.alt;
                v.loiterSet = true;
            }
            if (v.inAir) {
                goTo(v.loiterLat, v.loiterLon, v.loiterAlt, 2.0);
            }
        }
        if (v.main != MAIN_AUTO || v.sub != AUTO_LOITER) {
            if (v.main == MAIN_AUTO) {
                v.loiterSet = false;
            }
        }
    }
    Q_UNUSED(hold)

    // accelerate towards the wanted velocity (MPC_ACC_HOR 3 m/s², vertical 2 m/s²)
    const double an = clamp(wantN - v.vn, -3.0 * dt, 3.0 * dt);
    const double ae = clamp(wantE - v.ve, -3.0 * dt, 3.0 * dt);
    const double ad = clamp(wantD - v.vd, -2.0 * dt, 2.0 * dt);
    if (v.armed && v.inAir) {
        v.vn += an;
        v.ve += ae;
        v.vd += ad;
        double lat, lon;
        fromNe(kLat0, kLon0, here.n + v.vn * dt, here.e + v.ve * dt, lat, lon);
        v.lat = lat;
        v.lon = lon;
        v.alt -= v.vd * dt;
        if (v.alt <= 0.0 && v.vd >= 0.0) {
            // touchdown
            v.alt = 0;
            v.vn = v.ve = v.vd = 0;
            v.inAir = false;
            v.landedAt = t;
            if (v.main == MAIN_AUTO && (v.sub == AUTO_LAND || v.sub == AUTO_RTL || v.sub == AUTO_MISSION)) {
                _sendText(v, MAV_SEVERITY_INFO, QStringLiteral("Landing detected"));
                if (v.sub == AUTO_MISSION) {
                    _goToItem(v, static_cast<int>(v.mission.size()));
                }
                v.armed = false;
                _sendText(v, MAV_SEVERITY_INFO, QStringLiteral("Disarmed by landing"));
                _setMode(v, MAIN_AUTO, AUTO_LOITER);
            }
        }
        // attitude from the acceleration (and a little drag)
        const double c = std::cos(v.yaw), s = std::sin(v.yaw);
        const double aF = (an * c + ae * s) / dt, aR = (-an * s + ae * c) / dt;
        const double vF = v.vn * c + v.ve * s, vR = -v.vn * s + v.ve * c;
        v.pitch = 0.8 * v.pitch + 0.2 * (-std::atan((aF + 0.06 * vF) / kG));
        v.roll = 0.8 * v.roll + 0.2 * std::atan((aR + 0.06 * vR) / kG);
        // nose into the direction of travel (not in offboard: the guard keeps the heading)
        const double sp = std::hypot(v.vn, v.ve);
        if (sp > 1.0 && v.main != MAIN_OFFBOARD) {
            const double want = std::atan2(v.ve, v.vn);
            double d = std::remainder(want - v.yaw, 2 * 3.14159265358979323846);
            v.yaw += clamp(d, -qDegreesToRadians(90.0) * dt, qDegreesToRadians(90.0) * dt);
            v.yaw = std::remainder(v.yaw, 2 * 3.14159265358979323846);
        }
    } else if (v.armed && !v.inAir) {
        v.roll = v.pitch = 0;
    }

    // battery: ~2 %/min hovering, more when moving fast
    if (v.armed) {
        v.batt -= dt / 60.0 * (v.inAir ? 1.8 + 0.08 * std::hypot(v.vn, v.ve) : 0.2);
        v.batt = std::max(0.0, v.batt);
        if (!v.warned30 && v.batt < 30) {
            v.warned30 = true;
            _sendText(v, MAV_SEVERITY_WARNING, QStringLiteral("Low battery level! Return advised"));
        }
        if (!v.warned15 && v.batt < 15) {
            v.warned15 = true;
            _sendText(v, MAV_SEVERITY_CRITICAL, QStringLiteral("Critical battery level! Landing advised"));
        }
    }
}

uint8_t MLDemo::_oc() const
{
    auto *link = _config ? qobject_cast<MLDemoLink *>(_config->link()) : nullptr;
    return link ? link->outChannel() : 0;
}

void MLDemo::_send(const MLDemoVehicle &vIn, mavlink_message_t &msg)
{
    auto *link = _config ? qobject_cast<MLDemoLink *>(_config->link()) : nullptr;
    if (!link || vIn.linkCut) {
        return;
    }
    // re-finalize on the link's outgoing channel with this vehicle's own sequence number
    MLDemoVehicle &v = const_cast<MLDemoVehicle &>(vIn);
    mavlink_status_t *st = mavlink_get_channel_status(link->outChannel());
    st->current_tx_seq = v.txSeq;
    mavlink_finalize_message_chan(&msg, static_cast<uint8_t>(v.sysid), kComp, link->outChannel(), msg.len, msg.len, mavlink_get_crc_extra(&msg));
    v.txSeq = st->current_tx_seq;
    link->deliver(msg);
}

void MLDemo::_sendHeartbeat(MLDemoVehicle &v)
{
    mavlink_heartbeat_t hb{};
    hb.type = MAV_TYPE_QUADROTOR;
    hb.autopilot = MAV_AUTOPILOT_PX4;
    hb.base_mode = MAV_MODE_FLAG_CUSTOM_MODE_ENABLED | (v.armed ? MAV_MODE_FLAG_SAFETY_ARMED : 0)
                   | ((v.main == MAIN_AUTO || v.main == MAIN_OFFBOARD) ? (MAV_MODE_FLAG_AUTO_ENABLED | MAV_MODE_FLAG_GUIDED_ENABLED | MAV_MODE_FLAG_STABILIZE_ENABLED)
                                                                    : MAV_MODE_FLAG_STABILIZE_ENABLED);
    hb.custom_mode = (static_cast<uint32_t>(v.main) << 16) | (static_cast<uint32_t>(v.sub) << 24);
    hb.system_status = v.armed ? MAV_STATE_ACTIVE : MAV_STATE_STANDBY;
    hb.mavlink_version = 3;
    mavlink_message_t m;
    mavlink_msg_heartbeat_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &hb);
    _send(v, m);
}

void MLDemo::_sendTelemetry(MLDemoVehicle &v, bool fast, bool slow)
{
    const uint32_t ms = static_cast<uint32_t>(_now() * 1000.0);
    mavlink_message_t m;
    const double amsl = v.homeAmsl + v.alt;
    if (fast) {
        mavlink_global_position_int_t g{};
        g.time_boot_ms = ms;
        g.lat = static_cast<int32_t>(std::lround(v.lat * 1e7));
        g.lon = static_cast<int32_t>(std::lround(v.lon * 1e7));
        g.alt = static_cast<int32_t>(std::lround(amsl * 1000));
        g.relative_alt = static_cast<int32_t>(std::lround(v.alt * 1000));
        g.vx = static_cast<int16_t>(std::lround(v.vn * 100));
        g.vy = static_cast<int16_t>(std::lround(v.ve * 100));
        g.vz = static_cast<int16_t>(std::lround(v.vd * 100));
        g.hdg = static_cast<uint16_t>(std::lround(std::fmod(qRadiansToDegrees(v.yaw) + 360.0, 360.0) * 100));
        mavlink_msg_global_position_int_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &g);
        _send(v, m);
        mavlink_attitude_t a{};
        a.time_boot_ms = ms;
        a.roll = static_cast<float>(v.roll);
        a.pitch = static_cast<float>(v.pitch);
        a.yaw = static_cast<float>(v.yaw);
        mavlink_msg_attitude_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &a);
        _send(v, m);
        mavlink_vfr_hud_t h{};
        h.groundspeed = static_cast<float>(std::hypot(v.vn, v.ve));
        h.airspeed = h.groundspeed;
        h.heading = static_cast<int16_t>(std::lround(std::fmod(qRadiansToDegrees(v.yaw) + 360.0, 360.0)));
        h.throttle = static_cast<uint16_t>(v.inAir ? 52 : 0);
        h.alt = static_cast<float>(amsl);
        h.climb = static_cast<float>(-v.vd);
        mavlink_msg_vfr_hud_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &h);
        _send(v, m);
    }
    if (slow) {
        const double volt = 14.0 + 2.8 * v.batt / 100.0;
        const double amp = v.inAir ? 17.0 + 1.5 * std::hypot(v.vn, v.ve) : (v.armed ? 1.5 : 0.4);
        mavlink_sys_status_t s{};
        const uint32_t sensors = MAV_SYS_STATUS_SENSOR_3D_GYRO | MAV_SYS_STATUS_SENSOR_3D_ACCEL | MAV_SYS_STATUS_SENSOR_3D_MAG
                                 | MAV_SYS_STATUS_SENSOR_ABSOLUTE_PRESSURE | MAV_SYS_STATUS_SENSOR_GPS | MAV_SYS_STATUS_SENSOR_RC_RECEIVER
                                 | MAV_SYS_STATUS_SENSOR_ANGULAR_RATE_CONTROL | MAV_SYS_STATUS_SENSOR_ATTITUDE_STABILIZATION
                                 | MAV_SYS_STATUS_SENSOR_XY_POSITION_CONTROL | MAV_SYS_STATUS_SENSOR_MOTOR_OUTPUTS | MAV_SYS_STATUS_AHRS
                                 | MAV_SYS_STATUS_SENSOR_BATTERY;
        s.onboard_control_sensors_present = sensors;
        s.onboard_control_sensors_enabled = sensors;
        s.onboard_control_sensors_health = sensors;
        s.load = 320;
        s.voltage_battery = static_cast<uint16_t>(std::lround(volt * 1000));
        s.current_battery = static_cast<int16_t>(std::lround(amp * 100));
        s.battery_remaining = static_cast<int8_t>(std::lround(v.batt));
        mavlink_msg_sys_status_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &s);
        _send(v, m);
        mavlink_battery_status_t b{};
        b.id = 0;
        b.battery_function = MAV_BATTERY_FUNCTION_ALL;
        b.type = MAV_BATTERY_TYPE_LIPO;
        b.temperature = INT16_MAX;
        for (int i = 0; i < 10; i++) {
            b.voltages[i] = i < 4 ? static_cast<uint16_t>(std::lround(volt / 4 * 1000)) : UINT16_MAX;
        }
        b.current_battery = static_cast<int16_t>(std::lround(amp * 100));
        b.current_consumed = -1;
        b.energy_consumed = -1;
        b.battery_remaining = static_cast<int8_t>(std::lround(v.batt));
        b.charge_state = v.batt < 15 ? MAV_BATTERY_CHARGE_STATE_CRITICAL : (v.batt < 30 ? MAV_BATTERY_CHARGE_STATE_LOW : MAV_BATTERY_CHARGE_STATE_OK);
        mavlink_msg_battery_status_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &b);
        _send(v, m);
        mavlink_gps_raw_int_t gps{};
        gps.time_usec = static_cast<uint64_t>(_now() * 1e6);
        gps.fix_type = GPS_FIX_TYPE_3D_FIX;
        gps.lat = static_cast<int32_t>(std::lround(v.lat * 1e7));
        gps.lon = static_cast<int32_t>(std::lround(v.lon * 1e7));
        gps.alt = static_cast<int32_t>(std::lround(amsl * 1000));
        gps.eph = 70;
        gps.epv = 110;
        gps.vel = static_cast<uint16_t>(std::lround(std::hypot(v.vn, v.ve) * 100));
        gps.cog = static_cast<uint16_t>(std::lround(std::fmod(qRadiansToDegrees(std::atan2(v.ve, v.vn)) + 360.0, 360.0) * 100));
        gps.satellites_visible = 18;
        mavlink_msg_gps_raw_int_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &gps);
        _send(v, m);
        mavlink_extended_sys_state_t es{};
        es.landed_state = !v.armed || !v.inAir ? MAV_LANDED_STATE_ON_GROUND
                          : (v.main == MAIN_AUTO && v.sub == AUTO_LAND ? MAV_LANDED_STATE_LANDING
                          : (v.main == MAIN_AUTO && v.sub == AUTO_TAKEOFF ? MAV_LANDED_STATE_TAKEOFF : MAV_LANDED_STATE_IN_AIR));
        mavlink_msg_extended_sys_state_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &es);
        _send(v, m);
        mavlink_home_position_t hp{};
        hp.latitude = static_cast<int32_t>(std::lround(v.homeLat * 1e7));
        hp.longitude = static_cast<int32_t>(std::lround(v.homeLon * 1e7));
        hp.altitude = static_cast<int32_t>(std::lround(v.homeAmsl * 1000));
        hp.q[0] = 1;
        hp.time_usec = static_cast<uint64_t>(_now() * 1e6);
        mavlink_msg_home_position_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &hp);
        _send(v, m);
        mavlink_mission_current_t mc{};
        mc.seq = static_cast<uint16_t>(v.cur);
        mc.total = static_cast<uint16_t>(v.mission.size());
        mc.mission_state = v.mission.empty() ? MISSION_STATE_NO_MISSION
                           : (v.cur >= static_cast<int>(v.mission.size()) ? MISSION_STATE_COMPLETE
                           : (v.main == MAIN_AUTO && v.sub == AUTO_MISSION ? MISSION_STATE_ACTIVE : MISSION_STATE_NOT_STARTED));
        mavlink_msg_mission_current_encode_chan(static_cast<uint8_t>(v.sysid), kComp, _oc(), &m, &mc);
        _send(v, m);
    }
}
