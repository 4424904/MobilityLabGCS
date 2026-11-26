#include "MLAcactRuntime.h"

#include "LinkInterface.h"
#include "MAVLinkProtocol.h"
#include "MissionItem.h"
#include "MissionManager.h"
#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"
#include "Fact.h"
#include "GeoFenceManager.h"
#include "ParameterManager.h"
#include "QGCFenceCircle.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QLoggingCategory>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>

#include <algorithm>
#include <cmath>

Q_LOGGING_CATEGORY(MLAcactLog, "MobilityLab.ACACT")

using namespace acact;

namespace {
// PX4 custom modes (px4_custom_mode.h)
constexpr int PX4_MAIN_MANUAL = 1, PX4_MAIN_ALTCTL = 2, PX4_MAIN_POSCTL = 3, PX4_MAIN_AUTO = 4, PX4_MAIN_ACRO = 5,
              PX4_MAIN_OFFBOARD = 6, PX4_MAIN_STABILIZED = 7;
constexpr int PX4_AUTO_TAKEOFF = 2, PX4_AUTO_LOITER = 3, PX4_AUTO_MISSION = 4, PX4_AUTO_RTL = 5, PX4_AUTO_LAND = 6;

// guard.py constants
const QList<int> NAV_POS_CMDS = {16, 17, 18, 19, 21, 22};
constexpr int CMD_LOITER_UNLIM = 17;
constexpr int CMD_LAND = 21;

constexpr double LOOP_HZ = 20.0;
constexpr int    CMD_CHANGE_SPEED = 178;
constexpr double SET_CURRENT_WAIT = 2.0;   // [s] per MISSION_SET_CURRENT try (guard.py rev1)
constexpr int    SET_CURRENT_TRIES = 3;
constexpr double FENCE_RADIUS = 55.0;      // plan_gen.py

// mavsdk FlightMode → guard mode (guard.py MODE_MAP)
QString px4ModeName(uint32_t customMode)
{
    const int main = (customMode >> 16) & 0xFF;
    const int sub = (customMode >> 24) & 0xFF;
    switch (main) {
    case PX4_MAIN_OFFBOARD: return QStringLiteral("OFFBOARD");
    case PX4_MAIN_MANUAL: case PX4_MAIN_ALTCTL: case PX4_MAIN_POSCTL: case PX4_MAIN_ACRO: case PX4_MAIN_STABILIZED:
        return QStringLiteral("MANUAL");
    case PX4_MAIN_AUTO:
        switch (sub) {
        case PX4_AUTO_MISSION: return QStringLiteral("MISSION");
        case PX4_AUTO_LOITER: return QStringLiteral("HOLD");
        case PX4_AUTO_RTL: return QStringLiteral("RTL");
        case PX4_AUTO_LAND: return QStringLiteral("LAND");
        case PX4_AUTO_TAKEOFF: return QStringLiteral("TAKEOFF");
        default: return QStringLiteral("OTHER");
        }
    default:
        return QStringLiteral("OTHER");
    }
}

constexpr double kRadToDeg = 180.0 / 3.14159265358979323846;
constexpr double kDegToRad = 3.14159265358979323846 / 180.0;

// Config value by key (top-level fields and the ACACT gains)
using CfgRef = double &(*)(Config &);
struct ParamDef { const char *key; const char *label; const char *group; const char *unit; CfgRef ref; double lo, hi; };
#define CF(f) [](Config &c) -> double & { return c.f; }
const ParamDef kParams[] = {
    {"dSafe",          "개입 판단 거리 (D_SAFE)",        "판단",   "m",   CF(dSafe), 4, 40},
    {"dEmerg",         "긴급 거리 (D_EMERG)",            "판단",   "m",   CF(dEmerg), 2, 20},
    {"tLook",          "최근접 예측 시간 (T_LOOK)",       "판단",   "s",   CF(tLook), 2, 20},
    {"vSep",           "고도 분리 기준 (V_SEP)",          "판단",   "m",   CF(vSep), 1, 20},
    {"releaseMargin",  "해제 여유 (RELEASE_MARGIN)",      "해제",   "m",   CF(releaseMargin), 0, 10},
    {"releaseHold",    "해제 유지 시간 (RELEASE_HOLD)",   "해제",   "s",   CF(releaseHold), 0, 10},
    {"minOwnTime",     "최소 개입 시간 (MIN_OWN_TIME)",   "해제",   "s",   CF(minOwnTime), 0, 20},
    {"minTakeoverAlt", "개입 최저 고도",                  "해제",   "m",   CF(minTakeoverAlt), 1, 50},
    {"goalHandoff",    "목표 인계 거리 (GOAL_HANDOFF)",   "해제",   "m",   CF(goalHandoff), 0.5, 5},
    {"maxHSpeed",      "회피 최대 수평속도",              "회피",   "m/s", CF(maxHSpeed), 0.5, 10},
    {"maxClimb",       "긴급 상승 속도",                  "회피",   "m/s", CF(maxClimb), 0.2, 3},
    {"emergClimbMax",  "긴급 상승 최대량",                "회피",   "m",   CF(emergClimbMax), 0, 20},
    {"rs",             "반발 반경 (rs)",                  "ACACT", "m",   CF(acact.rs), 4, 40},
    {"ts",             "안전 시간 (ts)",                  "ACACT", "s",   CF(acact.ts), 0.5, 10},
    {"kpa",            "인력 게인 (kpa)",                 "ACACT", "",    CF(acact.kpa), 0, 5},
    {"kpp",            "위치 반발 게인 (kpp)",            "ACACT", "",    CF(acact.kpp), 0, 10},
    {"kpv",            "상대속도 반발 게인 (kpv)",        "ACACT", "",    CF(acact.kpv), 0, 5},
    {"kRh",            "우측 통행 게인 (k_rh)",           "ACACT", "",    CF(acact.k_rh), 0, 5},
    {"kCpa",           "사전 우측 회피 게인 (k_cpa)",     "ACACT", "m/s", CF(acact.k_cpa), 0, 10},
    {"staleT",         "텔레메트리 끊김 판정 (STALE_T)",  "통신",   "s",   CF(staleT), 0.5, 5},
    {"staleDropT",     "두절 기체 판단 제외 (STALE_DROP_T)", "통신", "s", CF(staleDropT), 5, 120},
    {"degradedMargin", "두절 시 추가 여유",               "통신",   "m",   CF(degradedMargin), 0, 10},
    {"dlLossT",        "데이터링크 상실 (DL_LOSS_T)",     "통신",   "s",   CF(dlLossT), 1, 30},
    {"demoAlt",        "시연 고도 (DEMO_ALT)",            "시나리오", "m", CF(demoAlt), 3, 50},
    {"takeoffAlt",     "이륙 고도 (TAKEOFF_ALT)",         "시나리오", "m", CF(takeoffAlt), 3, 30},
    {"scenarioSpeed",  "시나리오 속도",                   "시나리오", "m/s", CF(scenarioSpeed), 1, 8},
    {"transitSpeed",   "층 이동 속도",                    "시나리오", "m/s", CF(transitSpeed), 1, 10},
    {"autoSyncDelay",  "자동 진행 대기 (AUTO_SYNC_DELAY)", "진행",  "s",   CF(autoSyncDelay), 2, 30},
    {"battWarn",       "배터리 경고 (BATT_WARN)",          "진행",  "%",   CF(battWarn), 10, 80},
};
#undef CF

Config baseConfig(int n, const std::string &profile)
{
    Config c;
    c.profile = profile;
    c.applyFleetSize(n);
    return c;
}
} // namespace

struct MLAcactRuntime::VS {
    QPointer<Vehicle> v;
    QString id;
    int sysid = 0;
    int prio = 0;
    bool supported = false;       // PX4 multicopter: the guard may fly it
    bool connected = false;
    double lat = qQNaN(), lon = qQNaN();
    double absAlt = 0, relAlt = 0;
    double vn = 0, ve = 0, vd = 0;
    double yaw = 0;               // deg
    double yawHold = 0;
    double tPos = -1e9;
    QString mode = QStringLiteral("OTHER");
    bool inAir = false;
    bool armed = false;
    int cur = 0;
    int total = 0;
    double batt = qQNaN();
    int gpsFix = 0;
    int sats = 0;
    bool homeValid = false;
    double homeLat = 0, homeLon = 0;
    bool busy = false;
    double sp[3] = {0, 0, 0};     // velocity setpoint NED [m/s]
    double tTakeCmd = -1;
    double orphanSince = -1;
    double maxGap = 0;
    double xtMax = 0, xtSq = 0;
    long xtN = 0;
    double tRelease = -1e9;
    QList<double> switchLat;
    bool battWarned = false;
    double lastReload = -1e9;
    double takeoverCheckAt = -1;
    int hbSysid = 0;              // HEARTBEAT system id (MISSION_SET_CURRENT target, rev1)
    int paramSysid = -1;          // MAV_SYS_ID parameter (preflight)
    int rcOk = -1;                // RC receiver health from SYS_STATUS (-1 unknown)
    bool attSeen = false;
    double layer = 20.0;          // RTL / transit layer (config DRONES[].layer)
};

MLAcactRuntime::MLAcactRuntime(QObject *parent)
    : QObject(parent)
{
    _timer.setTimerType(Qt::PreciseTimer);
    _timer.setInterval(static_cast<int>(1000.0 / LOOP_HZ));
    connect(&_timer, &QTimer::timeout, this, &MLAcactRuntime::_tick);
    _startTimer.setSingleShot(true);
    connect(&_startTimer, &QTimer::timeout, this, &MLAcactRuntime::_startNext);

    _loadSettings();

    MultiVehicleManager *mvm = MultiVehicleManager::instance();
    connect(mvm, &MultiVehicleManager::vehicleAdded, this, &MLAcactRuntime::_vehicleAdded);
    connect(mvm, &MultiVehicleManager::vehicleRemoved, this, &MLAcactRuntime::_vehicleRemoved);
    for (int i = 0; i < mvm->vehicles()->count(); i++) {
        _attach(qobject_cast<Vehicle *>(mvm->vehicles()->get(i)));
    }
    // GCS closing: vehicles the guard is flying go to HOLD before the links close
    connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() { stop(); });
}

MLAcactRuntime::~MLAcactRuntime()
{
    qDeleteAll(_vs_);
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------
void MLAcactRuntime::_loadSettings()
{
    QSettings s;
    s.beginGroup(QStringLiteral("MobilityLab/ACACT"));
    _auto = s.value(QStringLiteral("auto"), true).toBool();
    _profile = s.value(QStringLiteral("profile"), QStringLiteral("oregon")).toString();
    if (!profiles().contains(_profile)) {
        _profile = QStringLiteral("oregon");
    }
    const QVariantMap homes = s.value(QStringLiteral("site/homes")).toMap();
    for (auto it = homes.cbegin(); it != homes.cend(); ++it) {
        const QVariantList ll = it.value().toList();
        if (ll.size() == 2) {
            _siteHomes[it.key()] = qMakePair(ll[0].toDouble(), ll[1].toDouble());
        }
    }
    s.beginGroup(QStringLiteral("params"));
    for (const QString &k : s.childKeys()) {
        _paramOverrides[k] = s.value(k).toDouble();
    }
    s.endGroup();
    if (s.value(QStringLiteral("site/set"), false).toBool()) {
        _frame = std::make_unique<Frame>(s.value(QStringLiteral("site/lat")).toDouble(), s.value(QStringLiteral("site/lon")).toDouble(),
                                         s.value(QStringLiteral("site/bearing")).toDouble());
        _siteRadius = s.value(QStringLiteral("site/radius"), 25.0).toDouble();
        _siteSet = true;
    }
    s.endGroup();
}

acact::Config MLAcactRuntime::_effectiveParams(int n) const
{
    Config p = baseConfig(n, _profile.toStdString());
    for (const ParamDef &d : kParams) {
        auto it = _paramOverrides.find(QString::fromLatin1(d.key));
        if (it != _paramOverrides.end()) {
            d.ref(p) = std::clamp(it.value(), d.lo, d.hi);
        }
    }
    return p;
}

QVariantList MLAcactRuntime::params() const
{
    const int n = std::max<qsizetype>(2, _vs_.size());
    Config def = baseConfig(static_cast<int>(n), _profile.toStdString());
    Config cur = _core ? _core->config() : _effectiveParams(static_cast<int>(n));
    QVariantList out;
    for (const ParamDef &d : kParams) {
        QVariantMap m;
        m[QStringLiteral("key")] = QString::fromLatin1(d.key);
        m[QStringLiteral("label")] = QString::fromUtf8(d.label);
        m[QStringLiteral("group")] = QString::fromUtf8(d.group);
        m[QStringLiteral("unit")] = QString::fromUtf8(d.unit);
        m[QStringLiteral("value")] = d.ref(cur);
        m[QStringLiteral("default")] = d.ref(def);
        m[QStringLiteral("min")] = d.lo;
        m[QStringLiteral("max")] = d.hi;
        m[QStringLiteral("changed")] = _paramOverrides.contains(QString::fromLatin1(d.key));
        out.append(m);
    }
    return out;
}

void MLAcactRuntime::setParam(const QString &key, double value)
{
    for (const ParamDef &d : kParams) {
        if (key == QLatin1String(d.key)) {
            value = std::clamp(value, d.lo, d.hi);
            _paramOverrides[key] = value;
            QSettings().setValue(QStringLiteral("MobilityLab/ACACT/params/") + key, value);
            if (_core) {
                d.ref(_core->config()) = value;
            }
            _event(QStringLiteral("CFG"), QStringLiteral("설정 변경: %1 = %2").arg(QString::fromUtf8(d.label)).arg(value));
            emit paramsChanged();
            return;
        }
    }
}

void MLAcactRuntime::resetParams()
{
    _paramOverrides.clear();
    QSettings().remove(QStringLiteral("MobilityLab/ACACT/params"));
    if (_core) {
        _core->config() = _effectiveParams(static_cast<int>(_vs_.size()));
    }
    _event(QStringLiteral("CFG"), QStringLiteral("설정 기본값 복원"));
    emit paramsChanged();
}

QVariantMap MLAcactRuntime::config() const
{
    const Config p = _core ? _core->config() : _effectiveParams(static_cast<int>(std::max<qsizetype>(2, _vs_.size())));
    return {
        {QStringLiteral("d_safe"), p.dSafe}, {QStringLiteral("d_emerg"), p.dEmerg}, {QStringLiteral("v_sep"), p.vSep},
        {QStringLiteral("t_look"), p.tLook}, {QStringLiteral("rs"), p.acact.rs}, {QStringLiteral("duo"), _vs_.size() == 2},
    };
}

QVariantMap MLAcactRuntime::site() const
{
    if (!_frame) {
        return {};
    }
    return {{QStringLiteral("lat"), _frame->lat0()}, {QStringLiteral("lon"), _frame->lon0()},
            {QStringLiteral("bearing"), _frame->bearingDeg()}, {QStringLiteral("radius"), _siteRadius},
            {QStringLiteral("fixed"), _siteSet}};
}

void MLAcactRuntime::setSite(double lat, double lon, double bearingDeg, double radius)
{
    if (_running) {
        _event(QStringLiteral("CFG"), QStringLiteral("가드 실행 중에는 시연 구역을 바꿀 수 없음"));
        return;
    }
    _frame = std::make_unique<Frame>(lat, lon, bearingDeg);
    _siteRadius = radius;
    _siteSet = true;
    QSettings s;
    s.beginGroup(QStringLiteral("MobilityLab/ACACT/site"));
    s.setValue(QStringLiteral("set"), true);
    s.setValue(QStringLiteral("lat"), lat);
    s.setValue(QStringLiteral("lon"), lon);
    s.setValue(QStringLiteral("bearing"), bearingDeg);
    s.setValue(QStringLiteral("radius"), radius);
    s.remove(QStringLiteral("homes"));
    _siteHomes.clear();
    _event(QStringLiteral("CFG"), QStringLiteral("시연 구역: %1, %2 · 방위 %3°").arg(lat, 0, 'f', 7).arg(lon, 0, 'f', 7).arg(bearingDeg, 0, 'f', 0));
    emit siteChanged();
}

void MLAcactRuntime::setSiteFromVehicles(double bearingDeg)
{
    // plan_gen.py --from-vehicles: real homes; bearing auto = mean heading of the vehicles (≤20° apart)
    if (_running) {
        _event(QStringLiteral("CFG"), QStringLiteral("가드 실행 중에는 시연 구역을 바꿀 수 없음"));
        return;
    }
    const QStringList ids = _activeIdList();
    QMap<QString, QPair<double, double>> homes;
    double sx = 0, cx = 0;
    QStringList heads;
    QList<double> hs;
    for (const QString &id : ids) {
        VS *d = const_cast<MLAcactRuntime *>(this)->_vs(id);
        const double la = d->homeValid ? d->homeLat : d->lat;
        const double lo = d->homeValid ? d->homeLon : d->lon;
        if (std::isnan(la) || std::isnan(lo)) {
            _event(id, QStringLiteral("위치(홈) 모름 → 시연 구역 설정 불가"));
            return;
        }
        homes[id] = qMakePair(la, lo);
        if (d->attSeen) {
            sx += std::sin(d->yaw * kDegToRad);
            cx += std::cos(d->yaw * kDegToRad);
            hs << d->yaw;
            heads << QStringLiteral("%1 %2°").arg(id).arg(std::fmod(d->yaw + 360.0, 360.0), 0, 'f', 0);
        }
    }
    if (homes.isEmpty()) {
        _event(QStringLiteral("CFG"), QStringLiteral("제어 가능한 PX4 기체(D1~D4)가 없어 시연 구역을 정할 수 없음"));
        return;
    }
    if (std::isnan(bearingDeg) || bearingDeg < 0) {
        if (hs.isEmpty()) {
            _event(QStringLiteral("CFG"), QStringLiteral("기수 방향을 아직 모름 → 방위를 직접 입력하세요"));
            return;
        }
        const double mean = std::fmod(std::atan2(sx, cx) * kRadToDeg + 360.0, 360.0);
        double worst = 0;
        for (double h : hs) {
            worst = std::max(worst, std::fabs(std::fmod(h - mean + 540.0, 360.0) - 180.0));
        }
        if (worst > 20.0) {
            _event(QStringLiteral("CFG"), QStringLiteral("✖ 기체 기수 방향이 서로 %1° 넘게 다릅니다 [%2] — 모든 기체 기수가 비행 방향을 똑같이 보게 놓고 다시")
                                              .arg(worst, 0, 'f', 0).arg(heads.join(QStringLiteral(", "))));
            return;
        }
        bearingDeg = mean;
        _event(QStringLiteral("CFG"), QStringLiteral("비행 방향(방위) 자동: %1° (기체 기수 방향 평균)").arg(bearingDeg, 0, 'f', 0));
    }
    // each real home moved back by its planned layout offset = centre candidate → mean
    std::vector<std::string> sids;
    for (const QString &id : ids) {
        sids.push_back(id.toStdString());
    }
    const Scenarios sc(_effectiveParams(ids.size()), sids);
    double clat = 0, clon = 0;
    for (auto it = homes.cbegin(); it != homes.cend(); ++it) {
        const Frame tmp(it.value().first, it.value().second, bearingDeg);
        const auto h = sc.home(it.key().toStdString());
        const auto c = tmp.frToLl(-h[0], -h[1]);
        clat += c[0];
        clon += c[1];
    }
    clat /= homes.size();
    clon /= homes.size();
    setSite(clat, clon, bearingDeg, _siteRadius);
    const Frame fr(clat, clon, bearingDeg);
    QVariantMap store;
    for (auto it = homes.cbegin(); it != homes.cend(); ++it) {
        const auto want = sc.home(it.key().toStdString());
        const auto got = fr.llToFr(it.value().first, it.value().second);
        const double dist = std::hypot(want[0] - got[0], want[1] - got[1]);
        if (dist > 3.0) {
            _event(it.key(), QStringLiteral("※ 위치가 권장 배치와 %1 m 다름 (권장 전방 %2, 우측 %3) — 기체 번호/위치 확인")
                                 .arg(dist, 0, 'f', 0).arg(want[0], 0, 'f', 0).arg(want[1], 0, 'f', 0));
        }
        store[it.key()] = QVariantList{it.value().first, it.value().second};
    }
    _siteHomes = homes;
    QSettings().setValue(QStringLiteral("MobilityLab/ACACT/site/homes"), store);
    emit siteChanged();
    emit scenariosChanged();
}

QStringList MLAcactRuntime::_activeIdList() const
{
    QStringList out;
    const Config c;
    for (const VS *d : _vs_) {
        if (d->supported && d->connected && c.slot(d->id.toStdString())) {
            out << d->id;
        }
    }
    std::sort(out.begin(), out.end());
    return out;
}

QString MLAcactRuntime::activeIds() const
{
    return _activeIdList().join(QStringLiteral(", "));
}

std::array<double, 2> MLAcactRuntime::_homeLl(const QString &id) const
{
    auto it = _siteHomes.find(id);
    if (it != _siteHomes.end()) {
        return {it.value().first, it.value().second};
    }
    std::vector<std::string> sids;
    for (const QString &x : _activeIdList()) {
        sids.push_back(x.toStdString());
    }
    const Scenarios sc(_effectiveParams(std::max<int>(1, static_cast<int>(sids.size()))), sids);
    const auto h = sc.home(id.toStdString());
    return _frame ? _frame->frToLl(h[0], h[1]) : std::array<double, 2>{qQNaN(), qQNaN()};
}

void MLAcactRuntime::setProfile(const QString &p)
{
    if (p == _profile || !profiles().contains(p)) {
        return;
    }
    if (_running) {
        _event(QStringLiteral("CFG"), QStringLiteral("가드 실행 중에는 배치 프로파일을 바꿀 수 없음"));
        emit paramsChanged();
        return;
    }
    _profile = p;
    QSettings().setValue(QStringLiteral("MobilityLab/ACACT/profile"), p);
    _event(QStringLiteral("CFG"), QStringLiteral("배치 프로파일: %1 — 시연 구역(기체 홈 기준)을 다시 설정하세요").arg(p));
    emit paramsChanged();
    emit scenariosChanged();
}

QVariantList MLAcactRuntime::scenarios() const
{
    std::vector<std::string> sids;
    for (const QString &x : _activeIdList()) {
        sids.push_back(x.toStdString());
    }
    QVariantList out;
    if (sids.empty()) {
        return out;
    }
    const Scenarios sc(_effectiveParams(static_cast<int>(sids.size())), sids);
    for (const ScenarioInfo &si : Scenarios::list()) {
        QVariantMap m;
        m[QStringLiteral("name")] = QString::fromStdString(si.name);
        m[QStringLiteral("title")] = QString::fromStdString(si.title);
        m[QStringLiteral("available")] = sc.available(si.name);
        out.append(m);
    }
    return out;
}

void MLAcactRuntime::loadScenario(const QString &name, const QString &mode)
{
    if (!_busy.isEmpty()) {
        _event(QStringLiteral("CMD"), QStringLiteral("진행 중인 작업이 있음: %1").arg(_busy));
        return;
    }
    for (VS *d : _vs_) {
        if (d->connected && (d->inAir || d->armed)) {
            _event(QStringLiteral("CMD"), QStringLiteral("load 는 모든 기체 지상·시동 꺼짐 상태에서만 가능"));
            return;
        }
    }
    if (!_frame) {
        _event(QStringLiteral("CMD"), QStringLiteral("시연 구역(중심·방위)을 먼저 설정하세요"));
        return;
    }
    if (mode != QLatin1String("demo") && mode != QLatin1String("rehearsal")) {
        _event(QStringLiteral("CMD"), QStringLiteral("모드는 demo 또는 rehearsal"));
        return;
    }
    const QStringList ids = _activeIdList();
    if (ids.isEmpty()) {
        _event(QStringLiteral("CMD"), QStringLiteral("제어 가능한 PX4 기체(D1~D4)가 없음"));
        return;
    }
    std::vector<std::string> sids;
    for (const QString &x : ids) {
        sids.push_back(x.toStdString());
    }
    const Scenarios sc(_effectiveParams(ids.size()), sids);
    bool known = false;
    for (const ScenarioInfo &si : Scenarios::list()) {
        known = known || si.name == name.toStdString();
    }
    if (!known || !sc.available(name.toStdString())) {
        _event(QStringLiteral("CMD"), QStringLiteral("시나리오 %1 은(는) 기체 %2대 구성에서 사용할 수 없음").arg(name).arg(ids.size()));
        return;
    }
    _scenario.clear();
    _scenarioMode.clear();
    _event(QStringLiteral("CMD"), QStringLiteral("시나리오 업로드: %1 / %2 → %3").arg(name, mode, ids.join(QStringLiteral(", "))));
    _uploadNext(ids, name, mode, true);
}

void MLAcactRuntime::_uploadNext(QStringList ids, QString name, QString mode, bool ok)
{
    if (ids.isEmpty()) {
        _busy.clear();
        if (ok) {
            _scenario = name;
            _scenarioMode = mode;
            _event(QStringLiteral("CMD"), QStringLiteral("시나리오 준비 완료: %1 / %2").arg(name, mode));
        } else {
            _event(QStringLiteral("CMD"), QStringLiteral("※ 시나리오 업로드 실패 — 기체별 메시지 확인 후 다시 load"));
        }
        runPreflight();
        emit updated();
        return;
    }
    const QString id = ids.takeFirst();
    VS *d = _vs(id);
    if (!d || !d->v || !d->connected) {
        _event(id, QStringLiteral("※ 업로드 실패: 연결 안 됨"));
        _uploadNext(ids, name, mode, false);
        return;
    }
    _busy = QStringLiteral("%1 업로드 중 (%2/%3)").arg(id, name, mode);
    emit updated();

    std::vector<std::string> sids;
    for (const QString &x : _activeIdList()) {
        sids.push_back(x.toStdString());
    }
    const Scenarios sc(_effectiveParams(static_cast<int>(sids.size())), sids);
    const auto built = sc.build(name.toStdString(), mode.toStdString());
    auto bit = built.find(id.toStdString());
    if (bit == built.end()) {
        _event(id, QStringLiteral("※ 업로드 실패: 시나리오에 이 기체 없음"));
        _uploadNext(ids, name, mode, false);
        return;
    }
    const auto home = _homeLl(id);
    auto r1 = [](double x) { char b[32]; std::snprintf(b, sizeof b, "%.1f", x); return std::atof(b); };   // round(x, 1)
    QList<MissionItem *> items;
    // seq 0 = planned home (PX4: QGC skips it on write)
    items << new MissionItem(0, MAV_CMD_NAV_WAYPOINT, MAV_FRAME_GLOBAL, 0, 0, 0, 0, home[0], home[1], 0, true, false);
    int seq = 1;
    for (const Item &it : bit->second) {
        MissionItem *mi = nullptr;
        if (it.type == Item::Speed) {
            mi = new MissionItem(seq, MAV_CMD_DO_CHANGE_SPEED, MAV_FRAME_MISSION, 1, it.v, -1, 0, 0, 0, 0, true, false);
        } else {
            std::array<double, 2> ll = home;
            if (it.type != Item::Takeoff && it.type != Item::Land) {
                ll = _frame->frToLl(it.f, it.r);
            }
            const double alt = r1(it.alt.value_or(0.0));
            switch (it.type) {
            case Item::Takeoff:
                mi = new MissionItem(seq, MAV_CMD_NAV_TAKEOFF, MAV_FRAME_GLOBAL_RELATIVE_ALT, 0, 0, 0, qQNaN(), ll[0], ll[1], alt, true, false);
                break;
            case Item::Wp:
                mi = new MissionItem(seq, MAV_CMD_NAV_WAYPOINT, MAV_FRAME_GLOBAL_RELATIVE_ALT, it.hasHold ? it.hold : 0.0, 0, 0, qQNaN(), ll[0], ll[1], alt, true, false);
                break;
            case Item::Sync:
                mi = new MissionItem(seq, MAV_CMD_NAV_LOITER_UNLIM, MAV_FRAME_GLOBAL_RELATIVE_ALT, 0, 0, 0, qQNaN(), ll[0], ll[1], alt, true, false);
                break;
            case Item::Land:
                mi = new MissionItem(seq, MAV_CMD_NAV_LAND, MAV_FRAME_GLOBAL_RELATIVE_ALT, 0, 0, 0, qQNaN(), ll[0], ll[1], 0, true, false);
                break;
            default:
                break;
            }
        }
        if (mi) {
            items << mi;
        }
        seq++;
    }
    const int expect = items.size() - 1;

    QPointer<Vehicle> v = d->v;
    MissionManager *mm = v->missionManager();
    if (mm->inProgress()) {
        qDeleteAll(items);
        _event(id, QStringLiteral("※ 업로드 실패: 미션 송수신이 진행 중 (잠시 후 다시)"));
        _uploadNext(ids, name, mode, false);
        return;
    }
    auto conn = std::make_shared<QMetaObject::Connection>();
    auto timer = std::make_shared<QTimer>();
    timer->setSingleShot(true);
    auto finish = [this, ids, name, mode, ok, conn, timer, id](bool good) {
        QObject::disconnect(*conn);
        timer->stop();
        QTimer::singleShot(0, this, [this, ids, name, mode, ok, good]() { _uploadNext(ids, name, mode, ok && good); });
    };
    connect(timer.get(), &QTimer::timeout, this, [this, id, finish]() {
        _event(id, QStringLiteral("※ 업로드 실패: 30초 안에 끝나지 않음"));
        finish(false);
    });
    *conn = connect(mm, &PlanManager::sendComplete, this, [this, v, id, expect, finish, conn, timer](bool error) {
        QObject::disconnect(*conn);
        if (error || !v) {
            _event(id, QStringLiteral("※ 업로드 실패 (기체 거부/통신)"));
            finish(false);
            return;
        }
        // geofence (plan_gen.py: inclusion circle FENCE_RADIUS around the centre); failure does not fail the mission
        if (v->geoFenceManager()->supported() && _frame) {
            QmlObjectListModel polygons, circles;
            circles.append(new QGCFenceCircle(QGeoCoordinate(_frame->lat0(), _frame->lon0()), FENCE_RADIUS, true, &circles));
            v->geoFenceManager()->sendToVehicle(QGeoCoordinate(), polygons, circles);
        }
        // read back and verify the item count (guard.py download_mission)
        *conn = connect(v->missionManager(), &PlanManager::newMissionItemsAvailable, this, [this, v, id, expect, finish](bool) {
            const int got = v ? v->missionManager()->missionItems().size() : -1;
            if (got != expect) {
                _event(id, QStringLiteral("※ 업로드 검증 실패 (%1 != %2)").arg(got).arg(expect));
                finish(false);
            } else {
                _event(id, QStringLiteral("업로드 OK (%1개)").arg(got));
                finish(true);
            }
        });
        QTimer::singleShot(500, this, [v]() {
            if (v) {
                v->missionManager()->loadFromVehicle();
            }
        });
    });
    timer->start(30000);
    mm->writeMissionItems(items);
}

void MLAcactRuntime::clearSite()
{
    if (_running) {
        return;
    }
    _frame.reset();
    _siteSet = false;
    QSettings().remove(QStringLiteral("MobilityLab/ACACT/site"));
    emit siteChanged();
}

QString MLAcactRuntime::supportScope() const
{
    return tr("ACACT 회피 제어: PX4 멀티콥터 (OFFBOARD 속도 제어, PX4 v1.16 SITL 검증). "
              "ArduPilot·헬리콥터·고정익 기체는 회피 대상(장애물)으로만 고려하며 제어하지 않습니다.");
}

QString MLAcactRuntime::logDir() const
{
    return QDir(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)).filePath(QStringLiteral("MobilityLab/ACACT"));
}

// ---------------------------------------------------------------------------
// Vehicles
// ---------------------------------------------------------------------------
MLAcactRuntime::VS *MLAcactRuntime::_vs(const QString &id)
{
    for (VS *d : _vs_) {
        if (d->id == id) {
            return d;
        }
    }
    return nullptr;
}

MLAcactRuntime::VS *MLAcactRuntime::_vsBySysid(int sysid)
{
    for (VS *d : _vs_) {
        if (d->sysid == sysid) {
            return d;
        }
    }
    return nullptr;
}

void MLAcactRuntime::_vehicleAdded(Vehicle *vehicle)
{
    _attach(vehicle);
}

void MLAcactRuntime::_vehicleRemoved(Vehicle *vehicle)
{
    for (VS *d : _vs_) {
        if (d->v == vehicle) {
            d->connected = false;
            if (_running) {
                _event(d->id, QStringLiteral("GCS 연결 해제 — 위치 불확실 기체로 계속 고려"));
            }
        }
    }
}

void MLAcactRuntime::_attach(Vehicle *vehicle)
{
    if (!vehicle) {
        return;
    }
    VS *d = _vsBySysid(vehicle->id());
    if (!d) {
        d = new VS;
        d->sysid = vehicle->id();
        d->id = QStringLiteral("D%1").arg(vehicle->id());
        _vs_.append(d);
        std::sort(_vs_.begin(), _vs_.end(), [](VS *a, VS *b) { return a->sysid < b->sysid; });
        for (int i = 0; i < _vs_.size(); i++) {
            _vs_[i]->prio = i;
        }
    }
    d->v = vehicle;
    d->connected = true;
    if (const acact::DroneSlot *slot = Config().slot(d->id.toStdString())) {
        d->layer = slot->layer;
    } else {
        d->layer = 20.0 + 6.0 * std::max(0, d->sysid - 1);
    }
    connect(vehicle->parameterManager(), &ParameterManager::parametersReadyChanged, this, [d, vehicle](bool ready) {
        if (ready && vehicle->parameterManager()->parameterExists(ParameterManager::defaultComponentId, QStringLiteral("MAV_SYS_ID"))) {
            d->paramSysid = vehicle->parameterManager()->getParameter(ParameterManager::defaultComponentId, QStringLiteral("MAV_SYS_ID"))->rawValue().toInt();
        }
    });
    emit scenariosChanged();
    d->supported = vehicle->px4Firmware() && vehicle->multiRotor();
    connect(vehicle, &Vehicle::mavlinkMessageReceived, this, [this, d](const mavlink_message_t &m) { _onMessage(d, m); });
    connect(vehicle, &Vehicle::firmwareTypeChanged, this, [d, vehicle]() { d->supported = vehicle->px4Firmware() && vehicle->multiRotor(); });
    connect(vehicle, &Vehicle::vehicleTypeChanged, this, [d, vehicle]() { d->supported = vehicle->px4Firmware() && vehicle->multiRotor(); });
    if (_running) {
        if (_core && !_core->own.count(d->id.toStdString())) {
            _core->own[d->id.toStdString()] = Own{};
        }
        _event(d->id, QStringLiteral("연결됨 (MAVLink %1, %2)").arg(d->sysid).arg(d->supported ? QStringLiteral("가드 제어 가능") : QStringLiteral("장애물로만 고려")));
    }
}

void MLAcactRuntime::_onMessage(VS *d, const mavlink_message_t &m)
{
    if (m.compid != MAV_COMP_ID_AUTOPILOT1 && m.msgid != MAVLINK_MSG_ID_HEARTBEAT) {
        return;
    }
    switch (m.msgid) {
    case MAVLINK_MSG_ID_HEARTBEAT: {
        if (m.compid != MAV_COMP_ID_AUTOPILOT1) {
            return;
        }
        mavlink_heartbeat_t hb;
        mavlink_msg_heartbeat_decode(&m, &hb);
        if (m.sysid != 0 && m.sysid != 255) {
            d->hbSysid = m.sysid;
        }
        d->armed = hb.base_mode & MAV_MODE_FLAG_SAFETY_ARMED;
        const QString mode = (hb.autopilot == MAV_AUTOPILOT_PX4) ? px4ModeName(hb.custom_mode) : QStringLiteral("OTHER");
        if (mode != d->mode) {
            const QString prev = d->mode;
            d->mode = mode;
            if (_running) {
                if (mode == QLatin1String("OFFBOARD") && d->tTakeCmd >= 0) {
                    d->switchLat.append(_now() - d->tTakeCmd);
                    d->tTakeCmd = -1;
                }
                const bool owned = _core && _core->own.count(d->id.toStdString()) && _core->own[d->id.toStdString()].owned;
                if (owned || mode == QLatin1String("RTL") || mode == QLatin1String("LAND") || mode == QLatin1String("MANUAL")) {
                    _event(d->id, QStringLiteral("모드 → %1").arg(mode));
                }
                if ((mode == QLatin1String("RTL") || mode == QLatin1String("LAND")) && d->inAir && _auto) {
                    _auto = false;
                    _event(QStringLiteral("AUTO"), QStringLiteral("%1 비상 귀환/착륙(%2) — 자동 진행 정지. 확인 후 자동 진행 켜기 또는 '대기 기체만 출발'").arg(d->id, mode));
                }
                if (mode == QLatin1String("MANUAL") && d->inAir) {
                    _event(d->id, QStringLiteral("※ 조종기 수동 개입 감지 — 가드는 이 기체를 피하기만 함"));
                    if (_auto) {
                        _auto = false;
                        _event(QStringLiteral("AUTO"), QStringLiteral("수동 개입으로 자동 진행 정지 — 상황 정리 후 자동 진행 켜기"));
                    }
                }
            }
            Q_UNUSED(prev)
        }
        break;
    }
    case MAVLINK_MSG_ID_GLOBAL_POSITION_INT: {
        mavlink_global_position_int_t p;
        mavlink_msg_global_position_int_decode(&m, &p);
        d->lat = p.lat / 1e7;
        d->lon = p.lon / 1e7;
        d->absAlt = p.alt / 1000.0;
        d->relAlt = p.relative_alt / 1000.0;
        d->vn = p.vx / 100.0;
        d->ve = p.vy / 100.0;
        d->vd = p.vz / 100.0;
        d->tPos = _now();
        break;
    }
    case MAVLINK_MSG_ID_ATTITUDE: {
        mavlink_attitude_t a;
        mavlink_msg_attitude_decode(&m, &a);
        d->yaw = a.yaw * kRadToDeg;
        d->attSeen = true;
        break;
    }
    case MAVLINK_MSG_ID_EXTENDED_SYS_STATE: {
        mavlink_extended_sys_state_t e;
        mavlink_msg_extended_sys_state_decode(&m, &e);
        if (e.landed_state == MAV_LANDED_STATE_IN_AIR || e.landed_state == MAV_LANDED_STATE_TAKEOFF || e.landed_state == MAV_LANDED_STATE_LANDING) {
            d->inAir = true;
        } else if (e.landed_state == MAV_LANDED_STATE_ON_GROUND) {
            d->inAir = false;
        }
        break;
    }
    case MAVLINK_MSG_ID_MISSION_CURRENT: {
        mavlink_mission_current_t mc;
        mavlink_msg_mission_current_decode(&m, &mc);
        d->cur = mc.seq;
        d->total = mc.total == UINT16_MAX ? 0 : mc.total;
        break;
    }
    case MAVLINK_MSG_ID_SYS_STATUS: {
        mavlink_sys_status_t st;
        mavlink_msg_sys_status_decode(&m, &st);
        d->batt = st.battery_remaining >= 0 ? st.battery_remaining : qQNaN();
        if (st.onboard_control_sensors_present & MAV_SYS_STATUS_SENSOR_RC_RECEIVER) {
            d->rcOk = (st.onboard_control_sensors_health & MAV_SYS_STATUS_SENSOR_RC_RECEIVER) ? 1 : 0;
        }
        break;
    }
    case MAVLINK_MSG_ID_GPS_RAW_INT: {
        mavlink_gps_raw_int_t g;
        mavlink_msg_gps_raw_int_decode(&m, &g);
        d->gpsFix = g.fix_type;
        d->sats = g.satellites_visible == 255 ? 0 : g.satellites_visible;
        break;
    }
    case MAVLINK_MSG_ID_HOME_POSITION: {
        mavlink_home_position_t h;
        mavlink_msg_home_position_decode(&m, &h);
        d->homeLat = h.latitude / 1e7;
        d->homeLon = h.longitude / 1e7;
        d->homeValid = true;
        break;
    }
    default:
        break;
    }
}

// ---------------------------------------------------------------------------
// Commands to one vehicle (over the GCS link that QGC uses for it)
// ---------------------------------------------------------------------------
void MLAcactRuntime::_sendSetpoint(VS *d)
{
    Vehicle *v = d->v;
    if (!v) {
        return;
    }
    SharedLinkInterfacePtr link = v->vehicleLinkManager()->primaryLink().lock();
    if (!link) {
        return;
    }
    // velocity (vx, vy, vz) + yaw, everything else ignored — same setpoint mavsdk's set_velocity_ned sends
    const uint16_t mask = POSITION_TARGET_TYPEMASK_X_IGNORE | POSITION_TARGET_TYPEMASK_Y_IGNORE | POSITION_TARGET_TYPEMASK_Z_IGNORE |
                          POSITION_TARGET_TYPEMASK_AX_IGNORE | POSITION_TARGET_TYPEMASK_AY_IGNORE | POSITION_TARGET_TYPEMASK_AZ_IGNORE |
                          POSITION_TARGET_TYPEMASK_YAW_RATE_IGNORE;
    mavlink_message_t msg;
    mavlink_msg_set_position_target_local_ned_pack_chan(
        static_cast<uint8_t>(MAVLinkProtocol::instance()->getSystemId()), static_cast<uint8_t>(MAVLinkProtocol::getComponentId()),
        link->mavlinkChannel(), &msg, static_cast<uint32_t>(_now() * 1000.0), static_cast<uint8_t>(v->id()),
        static_cast<uint8_t>(v->defaultComponentId()), MAV_FRAME_LOCAL_NED, mask, 0, 0, 0,
        static_cast<float>(d->sp[0]), static_cast<float>(d->sp[1]), static_cast<float>(d->sp[2]), 0, 0, 0,
        static_cast<float>(d->yawHold * kDegToRad), 0);
    v->sendMessageOnLinkThreadSafe(link.get(), msg);
}

void MLAcactRuntime::_setMode(VS *d, int mainMode, int subMode)
{
    if (!d->v) {
        return;
    }
    d->v->sendMavCommand(d->v->defaultComponentId(), MAV_CMD_DO_SET_MODE, false,
                         MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, mainMode, subMode);
}

void MLAcactRuntime::_hold(VS *d)
{
    if (!d->v) {
        return;
    }
    if (d->v->px4Firmware()) {
        _setMode(d, PX4_MAIN_AUTO, PX4_AUTO_LOITER);
    } else {
        d->v->pauseVehicle();
    }
}

void MLAcactRuntime::_startMission(VS *d)
{
    if (d->v && d->v->px4Firmware()) {
        _setMode(d, PX4_MAIN_AUTO, PX4_AUTO_MISSION);
    }
}

void MLAcactRuntime::_setCurrent(VS *d, int seq)
{
    Vehicle *v = d->v;
    if (!v) {
        return;
    }
    SharedLinkInterfacePtr link = v->vehicleLinkManager()->primaryLink().lock();
    if (!link) {
        return;
    }
    mavlink_message_t msg;
    mavlink_msg_mission_set_current_pack_chan(static_cast<uint8_t>(MAVLinkProtocol::instance()->getSystemId()),
                                              static_cast<uint8_t>(MAVLinkProtocol::getComponentId()), link->mavlinkChannel(), &msg,
                                              static_cast<uint8_t>(d->hbSysid ? d->hbSysid : v->id()), MAV_COMP_ID_AUTOPILOT1,
                                              static_cast<uint16_t>(seq));
    v->sendMessageOnLinkThreadSafe(link.get(), msg);
}

bool MLAcactRuntime::_canTake(VS *d)
{
    Own &o = _core->own[d->id.toStdString()];
    if ((d->mode == QLatin1String("MISSION") || d->mode == QLatin1String("OFFBOARD")) && _core->enabled && o.owned) {
        return true;
    }
    o.owned = false;
    if (d->mode == QLatin1String("MANUAL")) {
        _event(d->id, QStringLiteral("조종기 개입 중 → 가드 회피 명령 취소"));
    }
    return false;
}

void MLAcactRuntime::_takeover(VS *d, const Vec3 &v)
{
    d->yawHold = d->yaw;
    d->tTakeCmd = _now();
    const auto ne = _frame->frToNe(v[0], v[1]);
    d->sp[0] = ne[0];
    d->sp[1] = ne[1];
    d->sp[2] = -v[2];
    if (!_core->enabled || !_core->own[d->id.toStdString()].owned) {
        return;
    }
    // the setpoint stream is already running (20 Hz); push this one at once, then switch
    for (int i = 0; i < 3; i++) {
        _sendSetpoint(d);
    }
    // ★ never take a vehicle the pilot has taken in the meantime
    if (!_canTake(d)) {
        d->sp[0] = d->sp[1] = d->sp[2] = 0;
        return;
    }
    _setMode(d, PX4_MAIN_OFFBOARD, 0);
    d->takeoverCheckAt = _now() + 2.0;   // no OFFBOARD by then → failure handling (_tick)
    _event(d->id, QStringLiteral("회피 개입 (Offboard)"));
}

void MLAcactRuntime::_release(VS *d)
{
    if (d->mode != QLatin1String("OFFBOARD")) {   // the pilot or PX4 already took it: do not send it back to the mission
        d->sp[0] = d->sp[1] = d->sp[2] = 0;
        return;
    }
    _startMission(d);
    d->sp[0] = d->sp[1] = d->sp[2] = 0;
    _event(d->id, QStringLiteral("회피 완료 → 미션 복귀"));
}

void MLAcactRuntime::_stopHold(VS *d)
{
    d->sp[0] = d->sp[1] = d->sp[2] = 0;
    _sendSetpoint(d);
    _hold(d);
}

// ---------------------------------------------------------------------------
// Operation
// ---------------------------------------------------------------------------
void MLAcactRuntime::_rebuildCore()
{
    std::vector<std::string> ids;
    for (VS *d : _vs_) {
        ids.push_back(d->id.toStdString());
    }
    // DUO overrides follow the controlled fleet (config.apply_fleet), not traffic
    const int n = _activeIdList().size();
    _core = std::make_unique<GuardCore>(_effectiveParams(n > 0 ? n : static_cast<int>(_vs_.size())), ids);
}

bool MLAcactRuntime::start()
{
    if (_running) {
        return true;
    }
    if (_vs_.isEmpty()) {
        _event(QStringLiteral("SYS"), QStringLiteral("연결된 기체가 없어 가드를 시작할 수 없음"));
        return false;
    }
    _rebuildCore();
    _clock.start();
    _k = 0;
    _lastSyncT = -1e9;
    _autoSince = _autoBadSince = -1;
    _tickErrors = 0;
    for (VS *d : _vs_) {
        d->sp[0] = d->sp[1] = d->sp[2] = 0;
        d->yawHold = d->yaw;
        d->tPos = -1e9;           // fresh only after the next position report
        d->orphanSince = -1;
        d->takeoverCheckAt = -1;
        d->maxGap = 0;
        d->xtMax = d->xtSq = 0;
        d->xtN = 0;
        d->switchLat.clear();
        d->battWarned = false;
    }

    // log files
    QDir().mkpath(logDir());
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
    _logPath = QDir(logDir()).filePath(QStringLiteral("guard_%1.csv").arg(stamp));
    _sumPath = QDir(logDir()).filePath(QStringLiteral("guard_%1_summary.txt").arg(stamp));
    _logFile.setFileName(_logPath);
    if (_logFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream ts(&_logFile);
        ts << "t";
        for (VS *d : _vs_) {
            for (const char *c : {"mode", "f", "r", "alt", "vf", "vr", "own", "fresh", "wp"}) {
                ts << "," << d->id << "_" << c;
            }
        }
        ts << ",min_pair,min_dist\n";
    }
    _evFile.setFileName(QDir(logDir()).filePath(QStringLiteral("guard_%1_events.csv").arg(stamp)));
    if (_evFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        _evFile.write("t,who,event\n");
    }

    _running = true;
    _seen = true;
    QStringList list;
    for (VS *d : _vs_) {
        list << QStringLiteral("%1%2").arg(d->id, d->supported ? QString() : QStringLiteral("(장애물)"));
    }
    _event(QStringLiteral("SYS"), QStringLiteral("ACACT 가드 시작 — %1 · 로그 %2").arg(list.join(QStringLiteral(", ")), _logPath));
    if (!_frame) {
        _event(QStringLiteral("SYS"), QStringLiteral("시연 구역 미설정 → 첫 기체 위치를 원점으로 사용 (방위 0°)"));
    }
    runPreflight();
    _timer.start();
    emit runningChanged();
    emit paramsChanged();
    return true;
}

void MLAcactRuntime::stop()
{
    if (!_running) {
        return;
    }
    abortStart();
    for (VS *d : _vs_) {
        if (_core && _core->own[d->id.toStdString()].owned && d->connected) {
            _stopHold(d);
            _event(d->id, QStringLiteral("종료: 가드 개입 중이던 기체 HOLD"));
        }
    }
    _timer.stop();
    _running = false;
    _writeSummary();
    _event(QStringLiteral("SYS"), QStringLiteral("ACACT 가드 종료 — 요약 %1").arg(_sumPath));
    _logFile.close();
    _evFile.close();
    _avoiding = 0;
    _dronesV.clear();
    _pairsV.clear();
    emit runningChanged();
    emit updated();
}

void MLAcactRuntime::holdAll()
{
    if (!_running) {
        // without the guard: still stop every airborne vehicle
        for (VS *d : _vs_) {
            if (d->connected && d->inAir && d->mode != QLatin1String("MANUAL")) {
                _hold(d);
            }
        }
        _event(QStringLiteral("CMD"), QStringLiteral("전 기체 HOLD"));
        return;
    }
    _core->enabled = false;
    QList<VS *> live;
    for (VS *d : _vs_) {
        if (d->connected && d->inAir && d->mode != QLatin1String("MANUAL")) {   // pilot authority first
            live.append(d);
        }
    }
    for (VS *d : live) {
        d->sp[0] = d->sp[1] = d->sp[2] = 0;
        _sendSetpoint(d);
        _hold(d);
    }
    _event(QStringLiteral("CMD"), QStringLiteral("전 기체 HOLD (가드 일시정지) — '재개'로 미션 재개"));
    // a command that crossed this one: send HOLD again 1 s later to whoever is not holding
    QTimer::singleShot(1000, this, [this, live]() {
        QStringList again;
        for (VS *d : live) {
            if (!_vs_.contains(d)) {
                continue;
            }
            if (d->mode != QLatin1String("HOLD") && d->mode != QLatin1String("RTL") && d->mode != QLatin1String("LAND") && d->mode != QLatin1String("MANUAL")) {
                _hold(d);
                again << d->id;
            }
        }
        if (!again.isEmpty()) {
            _event(QStringLiteral("CMD"), QStringLiteral("HOLD 재전송: %1").arg(again.join(QStringLiteral(", "))));
        }
    });
    emit updated();
}

void MLAcactRuntime::resume()
{
    if (!_running) {
        return;
    }
    _core->enabled = true;
    for (VS *d : _vs_) {
        if (d->connected && d->inAir && (d->mode == QLatin1String("HOLD") || d->mode == QLatin1String("OFFBOARD")) &&
            !_core->own[d->id.toStdString()].owned) {
            _startMission(d);
        }
    }
    _event(QStringLiteral("CMD"), QStringLiteral("HOLD 기체 미션 재개, 가드 활성"));
    emit updated();
}

void MLAcactRuntime::setAutoMode(bool on)
{
    if (_auto == on) {
        return;
    }
    _auto = on;
    QSettings().setValue(QStringLiteral("MobilityLab/ACACT/auto"), on);
    _event(QStringLiteral("CMD"), QStringLiteral("자동 진행 %1 (대기 %2초, 착륙 %3)")
                                      .arg(on ? QStringLiteral("켜짐") : QStringLiteral("꺼짐"))
                                      .arg(_cfg().autoSyncDelay, 0, 'f', 0)
                                      .arg(_cfg().autoLand ? QStringLiteral("자동") : QStringLiteral("수동")));
    emit updated();
}

void MLAcactRuntime::_syncState(QList<VS *> &ready, QList<VS *> &notReady, bool &landing) const
{
    landing = false;
    for (VS *d : _vs_) {
        if (!d->connected || !d->inAir || !d->v) {
            continue;
        }
        bool atLoiter = false;
        const QList<MissionItem *> &items = d->v->missionManager()->missionItems();
        if (d->cur < items.size() && static_cast<int>(items[d->cur]->command()) == CMD_LOITER_UNLIM &&
            (d->mode == QLatin1String("MISSION") || d->mode == QLatin1String("HOLD")) && !std::isnan(d->lat) && _frame) {
            const MissionItem *it = items[d->cur];
            const auto p0 = _frame->llToFr(it->param5(), it->param6());
            const auto p1 = _frame->llToFr(d->lat, d->lon);
            atLoiter = std::hypot(p1[0] - p0[0], p1[1] - p0[1]) < 2.5 && std::abs(d->relAlt - it->param7()) < 1.5;
            if (d->cur + 1 < items.size() && static_cast<int>(items[d->cur + 1]->command()) == CMD_LAND) {
                landing = true;
            }
        }
        (atLoiter ? ready : notReady).append(d);
    }
}

void MLAcactRuntime::sync(bool force)
{
    if (!_running) {
        return;
    }
    if (!_core->enabled) {
        _event(QStringLiteral("CMD"), QStringLiteral("가드 일시정지(HOLD) 상태 — '재개' 후 '다음 단계'"));
        return;
    }
    QList<VS *> ready, notReady;
    bool landing = false;
    _syncState(ready, notReady, landing);
    if (ready.isEmpty()) {
        _event(QStringLiteral("CMD"), QStringLiteral("동기 대기(LOITER_UNLIM) 중인 기체 없음"));
        return;
    }
    if (!notReady.isEmpty() && !force) {
        QStringList ids;
        for (VS *d : notReady) ids << d->id;
        _event(QStringLiteral("CMD"), QStringLiteral("대기 미도달: %1 → 기다리거나 '대기 기체만 출발'").arg(ids.join(QStringLiteral(", "))));
        return;
    }
    _lastSyncT = _now();
    _autoSince = -1;
    // all at once (guard.py rev1: goto_next_item per vehicle, then mission for those in HOLD)
    QStringList ids;
    for (VS *d : ready) {
        ids << d->id;
    }
    auto remaining = std::make_shared<int>(ready.size());
    for (VS *d : ready) {
        const QString id = d->id;
        _gotoNextItem(d, [this, id, ids, remaining](bool ok, QString err) {
            if (!ok) {
                _event(id, QStringLiteral("※ 다음 항목 전환 실패: %1 — 상태 확인, 필요 시 '대기 기체만 출발' 또는 개별 조작").arg(err));
            }
            if (--(*remaining) == 0) {
                for (const QString &rid : ids) {
                    VS *x = _vs(rid);
                    if (x && x->mode == QLatin1String("HOLD")) {
                        _startMission(x);
                    }
                }
                _event(QStringLiteral("CMD"), QStringLiteral("동기 출발: %1").arg(ids.join(QStringLiteral(", "))));
            }
        });
    }
}

void MLAcactRuntime::_setCurrentChecked(VS *d, int k, std::function<void(bool, QString)> done)
{
    const QString id = d->id;
    const int cur0 = d->cur;
    auto attempt = std::make_shared<std::function<void(int)>>();
    *attempt = [this, id, k, cur0, done, attempt](int tryNo) {
        VS *x = _vs(id);
        if (!x || !x->v) {
            done(false, QStringLiteral("기체 없음"));
            return;
        }
        if (tryNo >= SET_CURRENT_TRIES) {
            done(false, QStringLiteral("PX4 가 미션 순서 %1 로 바뀌지 않음 (현재 %2, %3회 송신)").arg(k).arg(x->cur).arg(SET_CURRENT_TRIES));
            return;
        }
        _setCurrent(x, k);
        const double tEnd = _now() + SET_CURRENT_WAIT;
        auto poll = std::make_shared<std::function<void()>>();
        *poll = [this, id, k, cur0, tEnd, tryNo, done, attempt, poll]() {
            VS *y = _vs(id);
            if (!y) {
                done(false, QStringLiteral("기체 없음"));
                return;
            }
            // k or beyond (passed at once) or any change → PX4 accepted; never resend (it could move it back)
            if (y->cur >= k || y->cur != cur0) {
                done(true, QString());
                return;
            }
            if (_now() >= tEnd) {
                (*attempt)(tryNo + 1);
                return;
            }
            QTimer::singleShot(50, this, [poll]() { (*poll)(); });
        };
        QTimer::singleShot(50, this, [poll]() { (*poll)(); });
    };
    if (!d->hbSysid && !d->v) {
        done(false, QStringLiteral("기체 MAVLink ID 모름 → 미션 순서 변경 불가"));
        return;
    }
    (*attempt)(0);
}

void MLAcactRuntime::_gotoNextItem(VS *d, std::function<void(bool, QString)> done)
{
    if (!d->v) {
        done(false, QStringLiteral("기체 없음"));
        return;
    }
    const QList<MissionItem *> &items = d->v->missionManager()->missionItems();
    int k = d->cur + 1;
    double speed = -1;
    while (k < items.size() && !NAV_POS_CMDS.contains(static_cast<int>(items[k]->command()))) {
        if (static_cast<int>(items[k]->command()) == CMD_CHANGE_SPEED && items[k]->param2() > 0) {
            speed = items[k]->param2();
        }
        k++;
    }
    if (k >= items.size()) {
        done(false, QStringLiteral("다음 위치 항목 없음 (현재 %1)").arg(d->cur));
        return;
    }
    if (speed > 0) {
        d->v->sendMavCommand(d->v->defaultComponentId(), MAV_CMD_DO_CHANGE_SPEED, false, 1.0f, static_cast<float>(speed), -1.0f);
    }
    _setCurrentChecked(d, k, done);
}

void MLAcactRuntime::_autoTick(double t)
{
    if (!_auto || !_core->enabled || t - _lastSyncT < 3.0) {
        _autoSince = -1;
        return;
    }
    QList<VS *> ready, notReady;
    bool landing = false;
    _syncState(ready, notReady, landing);
    bool settled = !ready.isEmpty() && notReady.isEmpty();
    for (VS *d : ready) {
        settled = settled && std::hypot(d->vn, d->ve) < 0.5 && (t - d->tPos) < _core->config().staleT && !_core->own[d->id.toStdString()].owned;
    }
    if (!settled) {
        if (_autoBadSince < 0) {
            _autoBadSince = t;
        } else if (t - _autoBadSince > 1.0) {
            _autoSince = -1;
            _autoLandTold = false;
        }
        return;
    }
    _autoBadSince = -1;
    if (landing && !_core->config().autoLand) {
        if (!_autoLandTold) {
            _autoLandTold = true;
            _event(QStringLiteral("AUTO"), QStringLiteral("%1대 이륙지점 상공 도착 — 착륙은 확인 후 '다음 단계'").arg(ready.size()));
        }
        return;
    }
    if (_autoSince < 0) {
        _autoSince = t;
        if (_autoToldAt != _lastSyncT) {
            _autoToldAt = _lastSyncT;
            _event(QStringLiteral("AUTO"), QStringLiteral("%1대 도착 — %2초 후 %3 (멈추려면 전체 HOLD)")
                                               .arg(ready.size()).arg(_core->config().autoSyncDelay, 0, 'f', 0)
                                               .arg(landing ? QStringLiteral("착륙") : QStringLiteral("다음 기동")));
        }
    } else if (t - _autoSince >= _core->config().autoSyncDelay) {
        _autoSince = -1;
        _lastSyncT = t;
        sync(false);
    }
}

QVariantList MLAcactRuntime::runPreflight()
{
    _preflightV.clear();
    for (VS *d : _vs_) {
        QStringList msg;
        if (!d->connected) msg << QStringLiteral("연결 안 됨");
        if (!d->supported) msg << QStringLiteral("PX4 멀티콥터 아님 — 가드는 장애물로만 고려");
        if (d->gpsFix > 0 && d->gpsFix < 3) msg << QStringLiteral("GPS fix %1").arg(d->gpsFix);
        if (d->sats > 0 && d->sats < 10) msg << QStringLiteral("위성 %1개").arg(d->sats);
        if (!std::isnan(d->batt) && d->batt < 80) msg << QStringLiteral("배터리 %1%").arg(d->batt, 0, 'f', 0);
        if (d->paramSysid >= 0 && d->paramSysid != d->sysid) {
            msg << QStringLiteral("MAV_SYS_ID=%1 (기대 %2) — 모뎀/포트가 바뀌었을 수 있음").arg(d->paramSysid).arg(d->sysid);
        }
        if (_frame && d->attSeen && !d->inAir && d->supported) {
            const double diff = std::fabs(std::fmod(d->yaw - _frame->bearingDeg() + 540.0, 360.0) - 180.0);
            if (diff > 30.0) {
                msg << QStringLiteral("기수 방향 %1° 가 설정 방위 %2° 와 %3° 다름 — 방위를 잘못 넣었거나 기체 방향이 틀림")
                           .arg(std::fmod(d->yaw + 360.0, 360.0), 0, 'f', 0).arg(_frame->bearingDeg(), 0, 'f', 0).arg(diff, 0, 'f', 0);
            }
        }
        if (d->rcOk == 0) {
            msg << QStringLiteral("조종기 신호 없음 — 조종기 전원·바인딩 확인 (수동 개입 불가)");
        }
        if (_frame && d->supported && !std::isnan(d->lat) && _siteHomes.contains(d->id)) {
            const auto hp = _siteHomes.value(d->id);
            const auto p0 = _frame->llToFr(hp.first, hp.second);
            const auto p1 = _frame->llToFr(d->lat, d->lon);
            const double dist = std::hypot(p1[0] - p0[0], p1[1] - p0[1]);
            if (dist > 3.0) {
                msg << QStringLiteral("이륙 위치가 계획과 %1 m 다름").arg(dist, 0, 'f', 1);
            }
        }
        const QList<MissionItem *> items = d->v ? d->v->missionManager()->missionItems() : QList<MissionItem *>();
        if (items.isEmpty()) {
            msg << QStringLiteral("미션 없음");
        } else if (!std::isnan(d->lat) && !d->inAir && _frame) {
            for (const MissionItem *it : items) {
                if (NAV_POS_CMDS.contains(static_cast<int>(it->command())) && (it->param5() != 0 || it->param6() != 0)) {
                    const auto p0 = _frame->llToFr(it->param5(), it->param6());
                    const auto p1 = _frame->llToFr(d->lat, d->lon);
                    const double dist = std::hypot(p1[0] - p0[0], p1[1] - p0[1]);
                    if (dist > 5.0) {
                        msg << QStringLiteral("미션 이륙점이 현재 위치와 %1 m 다름 — 다른 기체 미션일 수 있음!").arg(dist, 0, 'f', 0);
                    }
                    break;
                }
            }
        }
        QVariantMap m;
        m[QStringLiteral("id")] = d->id;
        m[QStringLiteral("sysid")] = d->sysid;
        m[QStringLiteral("ok")] = msg.isEmpty() || (msg.size() == 1 && !d->supported);
        m[QStringLiteral("issues")] = msg;
        _preflightV.append(m);
    }
    emit updated();
    return _preflightV;
}

bool MLAcactRuntime::startFlight()
{
    if (!_running) {
        _event(QStringLiteral("CMD"), QStringLiteral("가드를 먼저 시작하세요"));
        return false;
    }
    if (!_core->enabled) {
        _event(QStringLiteral("CMD"), QStringLiteral("가드 일시정지 상태 — '재개' 후 다시"));
        return false;
    }
    for (VS *d : _vs_) {
        if (d->connected && d->inAir) {
            _event(QStringLiteral("CMD"), QStringLiteral("이미 비행 중인 기체가 있음 → 일괄 시작 불가 (기체별로 시작)"));
            return false;
        }
    }
    bool ok = true;
    for (const QVariant &p : runPreflight()) {
        const QVariantMap m = p.toMap();
        if (!m.value(QStringLiteral("ok")).toBool()) {
            ok = false;
            _event(m.value(QStringLiteral("id")).toString(), QStringLiteral("사전 점검: %1").arg(m.value(QStringLiteral("issues")).toStringList().join(QStringLiteral(" / "))));
        }
    }
    if (!ok) {
        _event(QStringLiteral("CMD"), QStringLiteral("사전 점검 실패 → 시작 취소"));
        return false;
    }
    // highest layer (last id) first, 5 s apart
    _startQueue.clear();
    for (int i = _vs_.size() - 1; i >= 0; i--) {
        if (_vs_[i]->supported && _vs_[i]->connected) {
            _startQueue.append(_vs_[i]->id);
        }
    }
    _event(QStringLiteral("CMD"), QStringLiteral("일괄 시작: %1 (5초 간격)").arg(_startQueue.join(QStringLiteral(" → "))));
    _startNext();
    emit updated();
    return true;
}

void MLAcactRuntime::abortStart()
{
    if (!_startQueue.isEmpty()) {
        _startQueue.clear();
        _startTimer.stop();
        _event(QStringLiteral("CMD"), QStringLiteral("일괄 시작 중단"));
        emit updated();
    }
}

void MLAcactRuntime::_startNext()
{
    if (_startQueue.isEmpty()) {
        return;
    }
    if (!_running || !_core->enabled) {
        _event(QStringLiteral("CMD"), QStringLiteral("일괄 시작 중단됨 (HOLD/종료)"));
        _startQueue.clear();
        emit updated();
        return;
    }
    VS *d = _vs(_startQueue.takeFirst());
    if (!d || !d->v) {
        _startNext();
        return;
    }
    d->v->setArmed(true, false);
    // mission mode once armed (MAV_CMD_DO_SET_MODE is queued behind the arm command by QGC)
    QPointer<Vehicle> v = d->v;
    QTimer::singleShot(1500, this, [this, d, v]() {
        if (!v || !_vs_.contains(d)) {
            return;
        }
        if (!d->armed) {
            _event(d->id, QStringLiteral("※ 시동 실패 → 나머지 기체 시작 중단"));
            _startQueue.clear();
            _startTimer.stop();
            emit updated();
            return;
        }
        _startMission(d);
        _event(d->id, QStringLiteral("시동·미션 시작"));
    });
    if (!_startQueue.isEmpty()) {
        _startTimer.start(5000);
    }
    emit updated();
}

void MLAcactRuntime::operatorCommand(int sysid, const QString &what)
{
    VS *d = _vsBySysid(sysid);
    if (!d || !_running || !_core) {
        return;
    }
    Own &o = _core->own[d->id.toStdString()];
    if (o.owned) {
        o.owned = false;
        o.lock = true;        // until its mission is resumed, as for a pilot mode change
        d->sp[0] = d->sp[1] = d->sp[2] = 0;
        _event(d->id, QStringLiteral("운용자 명령 '%1' 우선 → 가드 해제 (미션 재개 시 다시 감시)").arg(what));
        emit updated();
    }
}

bool MLAcactRuntime::owns(int sysid) const
{
    for (VS *d : _vs_) {
        if (d->sysid == sysid) {
            return _running && _core && _core->own.count(d->id.toStdString()) && _core->own.at(d->id.toStdString()).owned;
        }
    }
    return false;
}

bool MLAcactRuntime::sendLine(const QString &line)
{
    const QString l = line.trimmed().toLower();
    if (l == QLatin1String("h")) { holdAll(); return true; }
    if (!_running) { return false; }
    if (l == QLatin1String("r")) { resume(); return true; }
    if (l == QLatin1String("g")) { sync(false); return true; }
    if (l == QLatin1String("g!")) { sync(true); return true; }
    if (l == QLatin1String("auto on")) { setAutoMode(true); return true; }
    if (l == QLatin1String("auto off")) { setAutoMode(false); return true; }
    if (l == QLatin1String("start")) { return startFlight(); }
    if (l == QLatin1String("s")) { runPreflight(); return true; }
    return false;
}

QVariantMap MLAcactRuntime::droneForSysid(int sysid) const
{
    for (const QVariant &d : _dronesV) {
        const QVariantMap m = d.toMap();
        if (m.value(QStringLiteral("sysid")).toInt() == sysid) {
            return m;
        }
    }
    return {};
}

QVariantList MLAcactRuntime::minSeparation() const
{
    QVariantList out;
    if (!_core) {
        return out;
    }
    for (const auto &[k, v] : _core->minSep) {
        auto it = _core->min3d.find(k);
        out.append(QVariantMap{{QStringLiteral("a"), QString::fromStdString(k.first)}, {QStringLiteral("b"), QString::fromStdString(k.second)},
                               {QStringLiteral("sameLayer"), v}, {QStringLiteral("d3"), it == _core->min3d.end() ? qQNaN() : it->second}});
    }
    return out;
}

// ---------------------------------------------------------------------------
// Guard loop (guard.py tick)
// ---------------------------------------------------------------------------
std::pair<int, int> MLAcactRuntime::_goalOf(VS *d) const
{
    if (!d->v || !_frame) {
        return {-1, -1};
    }
    const QList<MissionItem *> &items = d->v->missionManager()->missionItems();
    for (int k = d->cur; k < items.size(); k++) {
        const MissionItem *it = items[k];
        if (NAV_POS_CMDS.contains(static_cast<int>(it->command())) && (it->param5() != 0 || it->param6() != 0)) {
            int prev = -1;
            for (int j = k - 1; j >= 0; j--) {
                const MissionItem *pj = items[j];
                if (NAV_POS_CMDS.contains(static_cast<int>(pj->command())) && (pj->param5() != 0 || pj->param6() != 0)) {
                    prev = j;
                    break;
                }
            }
            return {k, prev};
        }
    }
    return {-1, -1};
}

void MLAcactRuntime::_tick()
{
    const double t = _now();
    try {
        _autoTick(t);

        // frame: from the site, otherwise the first vehicle with a position (bearing 0)
        if (!_frame) {
            for (VS *d : _vs_) {
                if (!std::isnan(d->lat)) {
                    _frame = std::make_unique<Frame>(d->lat, d->lon, 0.0);
                    _event(QStringLiteral("SYS"), QStringLiteral("시연 구역 원점 = %1 현재 위치 (방위 0°)").arg(d->id));
                    emit siteChanged();
                    break;
                }
            }
        }

        std::vector<DroneIn> ins;
        for (VS *d : _vs_) {
            // mission changed on the vehicle (uploaded by another tool / plan view) → reload
            if (d->connected && d->v && d->total && d->total != d->v->missionManager()->missionItems().size() &&
                !d->v->missionManager()->inProgress() && t - d->lastReload > 3.0) {
                d->lastReload = t;
                d->v->missionManager()->loadFromVehicle();
                _event(d->id, QStringLiteral("미션 변경 감지 → 다시 받기"));
            }
            if (std::isnan(d->lat) || !_frame) {
                continue;
            }
            const auto fr = _frame->llToFr(d->lat, d->lon);
            const auto vfr = _frame->neToFr(d->vn, d->ve);
            const double age = t - d->tPos;
            if (d->inAir) {
                d->maxGap = std::max(d->maxGap, age);
                if (!std::isnan(d->batt) && d->batt < _core->config().battWarn && !d->battWarned) {
                    d->battWarned = true;
                    _event(d->id, QStringLiteral("※ 배터리 %1% — 이번 기동 후 착륙 권장").arg(d->batt, 0, 'f', 0));
                }
            }
            DroneIn in;
            in.id = d->id.toStdString();
            in.prio = d->prio;
            in.fresh = age < _core->config().staleT;
            in.age = age;
            in.f = fr[0];
            in.r = fr[1];
            in.u = d->absAlt;
            in.vf = vfr[0];
            in.vr = vfr[1];
            in.vu = -d->vd;
            in.relAlt = d->relAlt;
            in.inAir = d->inAir;
            in.mode = d->supported ? d->mode.toStdString() : std::string("OTHER");
            const auto [gi, pi] = _goalOf(d);
            if (gi >= 0) {
                const MissionItem *it = d->v->missionManager()->missionItems()[gi];
                in.goal = _frame->llToFr(it->param5(), it->param6());
                const int cmd = static_cast<int>(it->command());
                in.goalHold = cmd == 17 || cmd == 19 || (cmd == 16 && it->param1() > 0);
                in.goalAlt = it->param7();
                // path-following error (not while the guard flies it, straight legs > 5 m)
                if (pi >= 0 && d->mode == QLatin1String("MISSION") && !_core->own[in.id].owned && t - d->tRelease > 10.0) {
                    const MissionItem *pv = d->v->missionManager()->missionItems()[pi];
                    const auto a = _frame->llToFr(pv->param5(), pv->param6());
                    const double lf = (*in.goal)[0] - a[0], lr = (*in.goal)[1] - a[1];
                    const double L = std::hypot(lf, lr);
                    if (L > 5.0) {
                        const double s = ((in.f - a[0]) * lf + (in.r - a[1]) * lr) / (L * L);
                        if (s > 0.1 && s < 0.9) {
                            const double xt = std::abs((in.f - a[0]) * lr - (in.r - a[1]) * lf) / L;
                            d->xtMax = std::max(d->xtMax, xt);
                            d->xtSq += xt * xt;
                            d->xtN++;
                        }
                    }
                }
            }
            in.rtlAlt = d->layer;   // config.py DRONES[].layer
            if (d->homeValid) {
                in.home = _frame->llToFr(d->homeLat, d->homeLon);
            }
            if (!_core->own.count(in.id)) {
                _core->own[in.id] = Own{};
            }
            ins.push_back(in);
        }

        // takeover that never reached OFFBOARD → HOLD (guard.py: offboard.start() failed)
        for (VS *d : _vs_) {
            if (d->takeoverCheckAt > 0 && t >= d->takeoverCheckAt) {
                d->takeoverCheckAt = -1;
                Own &o = _core->own[d->id.toStdString()];
                if (o.owned && d->mode != QLatin1String("OFFBOARD")) {
                    o.owned = false;
                    _event(d->id, QStringLiteral("Offboard 전환 실패 (모드 %1) → HOLD").arg(d->mode));
                    _stopHold(d);
                }
            }
        }

        // safety net: OFFBOARD but not held by the guard (race, another tool…) → stop and HOLD after 1 s
        for (VS *d : _vs_) {
            if (d->supported && d->connected && d->inAir && d->mode == QLatin1String("OFFBOARD") && !_core->own[d->id.toStdString()].owned && !d->busy) {
                if (d->orphanSince < 0) {
                    d->orphanSince = t;
                } else if (t - d->orphanSince > 1.0) {
                    d->orphanSince = t + 2.0;
                    _event(d->id, QStringLiteral("※ 가드 미관리 Offboard 감지 → 정지·HOLD"));
                    _stopHold(d);
                }
            } else {
                d->orphanSince = -1;
            }
        }

        const std::vector<Command> cmds = _core->step(t, ins);
        for (const Command &c : cmds) {
            if (c.kind == CmdKind::Event) {
                _event(QString::fromStdString(c.id), QString::fromStdString(c.text));
                continue;
            }
            VS *d = _vs(QString::fromStdString(c.id));
            if (!d || !d->supported) {
                continue;
            }
            if (c.kind == CmdKind::Takeover) {
                _takeover(d, c.v);
            } else if (c.kind == CmdKind::Vel) {
                const auto ne = _frame->frToNe(c.v[0], c.v[1]);
                d->sp[0] = ne[0];
                d->sp[1] = ne[1];
                d->sp[2] = -c.v[2];
            } else if (c.kind == CmdKind::Release) {
                d->tRelease = t;
                _release(d);
            } else if (c.kind == CmdKind::Advance) {
                // rev1: keep OFFBOARD, move the mission sequence on (PX4 does not advance it in OFFBOARD)
                if (d->mode == QLatin1String("OFFBOARD") && d->v && d->cur + 1 < d->v->missionManager()->missionItems().size()) {
                    _gotoNextItem(d, [](bool, QString) {});
                }
            }
        }

        // setpoint stream (20 Hz) to every PX4 vehicle the guard may fly; zero unless avoiding.
        // PX4 ignores it outside OFFBOARD; it is what lets a takeover switch at once.
        for (VS *d : _vs_) {
            if (d->supported && d->connected) {
                _sendSetpoint(d);
            }
        }

        if (_k % 2 == 0) {
            _writeLog(t, ins);
        }
        if (_k % 4 == 0) {
            _publish(ins);
        }
    } catch (const std::exception &e) {
        _tickErrors++;
        _event(QStringLiteral("SYS"), QStringLiteral("※ 가드 내부 오류 (%1) → 회피 중 기체 HOLD").arg(QString::fromUtf8(e.what())));
        for (VS *d : _vs_) {
            if (_core && _core->own[d->id.toStdString()].owned) {
                _core->own[d->id.toStdString()].owned = false;
                _stopHold(d);
            }
        }
    }
    _k++;
}

void MLAcactRuntime::_writeLog(double t, const std::vector<DroneIn> &ins)
{
    if (!_logFile.isOpen()) {
        return;
    }
    QTextStream ts(&_logFile);
    ts << QString::number(t, 'f', 2);
    for (VS *d : _vs_) {
        const DroneIn *x = nullptr;
        for (const DroneIn &i : ins) {
            if (i.id == d->id.toStdString()) {
                x = &i;
            }
        }
        if (!x) {
            ts << ",,,,,,,,,";
            continue;
        }
        ts << "," << QString::fromStdString(x->mode) << "," << QString::number(x->f, 'f', 2) << "," << QString::number(x->r, 'f', 2)
           << "," << QString::number(x->relAlt, 'f', 2) << "," << QString::number(x->vf, 'f', 2) << "," << QString::number(x->vr, 'f', 2)
           << "," << int(_core->own[x->id].owned) << "," << int(x->fresh) << "," << d->cur;
    }
    QString mp, md;
    double best = 1e18;
    for (const auto &[k, pe] : _core->pairs) {
        const double dd = std::hypot(pe.dNow, pe.dz);
        if (dd < best) {
            best = dd;
            mp = QStringLiteral("%1-%2").arg(QString::fromStdString(k.first), QString::fromStdString(k.second));
            md = QString::number(dd, 'f', 2);
        }
    }
    ts << "," << mp << "," << md << "\n";
}

void MLAcactRuntime::_publish(const std::vector<DroneIn> &ins)
{
    QVariantList drones;
    int avoiding = 0;
    for (VS *d : _vs_) {
        const DroneIn *x = nullptr;
        for (const DroneIn &i : ins) {
            if (i.id == d->id.toStdString()) {
                x = &i;
            }
        }
        const Own &o = _core->own[d->id.toStdString()];
        avoiding += o.owned ? 1 : 0;
        QVariantMap m;
        m[QStringLiteral("id")] = d->id;
        m[QStringLiteral("sysid")] = d->sysid;
        m[QStringLiteral("connected")] = d->connected;
        m[QStringLiteral("supported")] = d->supported;
        m[QStringLiteral("lat")] = std::isnan(d->lat) ? QVariant() : QVariant(d->lat);
        m[QStringLiteral("lon")] = std::isnan(d->lon) ? QVariant() : QVariant(d->lon);
        m[QStringLiteral("alt")] = d->relAlt;
        m[QStringLiteral("vn")] = d->vn;
        m[QStringLiteral("ve")] = d->ve;
        m[QStringLiteral("mode")] = d->mode;
        m[QStringLiteral("own")] = o.owned;
        m[QStringLiteral("yield")] = o.yielding;
        m[QStringLiteral("lock")] = o.lock;
        m[QStringLiteral("fresh")] = x ? x->fresh : false;
        m[QStringLiteral("batt")] = std::isnan(d->batt) ? QVariant() : QVariant(d->batt);
        m[QStringLiteral("seq")] = d->cur;
        m[QStringLiteral("total")] = d->v ? d->v->missionManager()->missionItems().size() : 0;
        m[QStringLiteral("takeovers")] = o.takeovers;
        m[QStringLiteral("ownedTime")] = o.ownedTime;
        if (x && x->goal && _frame) {
            const auto ll = _frame->frToLl((*x->goal)[0], (*x->goal)[1]);
            m[QStringLiteral("goal")] = QVariantList{ll[0], ll[1]};
        }
        drones.append(m);
    }
    QVariantList pairs;
    double closest = qQNaN();
    int worst = 0;
    for (const auto &[k, pe] : _core->pairs) {
        auto ms = _core->minSep.find(k);
        pairs.append(QVariantMap{{QStringLiteral("a"), QString::fromStdString(k.first)}, {QStringLiteral("b"), QString::fromStdString(k.second)},
                                 {QStringLiteral("d"), pe.dNow}, {QStringLiteral("dz"), pe.dz}, {QStringLiteral("level"), pe.level},
                                 {QStringLiteral("cpa"), pe.dCpa}, {QStringLiteral("tcpa"), pe.tCpa},
                                 {QStringLiteral("min"), ms == _core->minSep.end() ? QVariant() : QVariant(ms->second)}});
        const double sep = std::hypot(pe.dNow, pe.dz);
        if (std::isnan(closest) || sep < closest) {
            closest = sep;
        }
        worst = std::max(worst, pe.level);
    }
    _dronesV = drones;
    _pairsV = pairs;
    _avoiding = avoiding;
    _closest = closest;
    _worstLevel = worst;
    emit updated();
}

void MLAcactRuntime::_event(const QString &who, const QString &text)
{
    const double t = _now();
    qCInfo(MLAcactLog).noquote() << QStringLiteral("[%1] %2 | %3").arg(t, 7, 'f', 1).arg(who, 5).arg(text);
    if (_evFile.isOpen()) {
        QString safe = text;
        safe.replace(QLatin1Char('"'), QLatin1Char('\''));
        _evFile.write(QStringLiteral("%1,%2,\"%3\"\n").arg(t, 0, 'f', 2).arg(who, safe).toUtf8());
        _evFile.flush();
    }
    emit guardEvent(++_eventSeq, t, who, text);
}

void MLAcactRuntime::_writeSummary()
{
    if (!_core) {
        return;
    }
    QStringList lines;
    lines << QStringLiteral("ACACT Guard 결과 요약 (MobilityLab GCS 내장)") << QString(40, QLatin1Char('='));
    lines << QStringLiteral("기록: %1").arg(_logPath);
    lines << QStringLiteral("\n[기체 간 최소 거리]  (같은 층 = 고도차 %1 m 이내일 때의 수평거리)").arg(_core->config().vSep, 0, 'f', 0);
    for (const auto &[k, v] : _core->minSep) {
        auto it = _core->min3d.find(k);
        const double v3 = it == _core->min3d.end() ? qQNaN() : it->second;
        lines << QStringLiteral("  %1-%2: 같은 층 %3 m / 3D %4 m  %5")
                     .arg(QString::fromStdString(k.first), QString::fromStdString(k.second))
                     .arg(v, 5, 'f', 1).arg(v3, 5, 'f', 1).arg(v >= 5.0 ? QStringLiteral("OK") : QStringLiteral("※ 5 m 미만"));
    }
    lines << QStringLiteral("\n[가드 개입]");
    for (VS *d : _vs_) {
        const Own &o = _core->own[d->id.toStdString()];
        const double rms = d->xtN ? std::sqrt(d->xtSq / d->xtN) : qQNaN();
        lines << QStringLiteral("  %1: 개입 %2회, 개입 시간 %3 s, 경로추종 오차 최대 %4 m / RMS %5 m (회피 후 10초 제외)")
                     .arg(d->id).arg(o.takeovers).arg(o.ownedTime, 5, 'f', 1).arg(d->xtMax, 4, 'f', 1).arg(rms, 4, 'f', 1);
    }
    lines << QStringLiteral("\n[링크 품질]  (수신 공백 < 0.5 s, 전환 지연 < 0.7 s 권장)");
    for (VS *d : _vs_) {
        QString sw = QStringLiteral("-");
        if (!d->switchLat.isEmpty()) {
            double mx = 0, sum = 0;
            for (double x : d->switchLat) { mx = std::max(mx, x); sum += x; }
            sw = QStringLiteral("%1 s (평균 %2)").arg(mx, 0, 'f', 2).arg(sum / d->switchLat.size(), 0, 'f', 2);
        }
        lines << QStringLiteral("  %1: 비행 중 최대 수신 공백 %2 s, Offboard 전환 지연 최대 %3").arg(d->id).arg(d->maxGap, 4, 'f', 2).arg(sw);
    }
    if (_tickErrors) {
        lines << QStringLiteral("\n※ 가드 내부 오류 %1회").arg(_tickErrors);
    }
    QFile f(_sumPath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        f.write(lines.join(QLatin1Char('\n')).toUtf8());
        f.write("\n");
    }
    qCInfo(MLAcactLog).noquote() << lines.join(QLatin1Char('\n'));
}
