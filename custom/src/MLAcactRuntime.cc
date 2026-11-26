#include "MLAcactRuntime.h"

#ifndef ML_GCS_VERSION
#define ML_GCS_VERSION "dev"
#endif

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
#include "QGCFencePolygon.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDir>
#include <QtCore/QRegularExpression>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QUrl>
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

// user-mission check limits (AcactMissionCheck Limits)
using LimRef = double &(*)(acact::Limits &);
struct LimDef { const char *key; const char *label; const char *unit; LimRef ref; double lo, hi; };
#define LF(f) [](acact::Limits &l) -> double & { return l.f; }
const LimDef kLimits[] = {
    {"limMaxAlt",    "미션 최고 고도",              "m",   LF(maxAlt), 10, 500},
    {"limMinAlt",    "미션 최저 순항 고도",          "m",   LF(minAlt), 1, 30},
    {"limMaxRange",  "홈에서 최대 거리",            "m",   LF(maxRange), 50, 20000},
    {"limTakeoffTol","이륙점 허용 오차",            "m",   LF(takeoffTol), 1, 30},
    {"limPadMin",    "이착륙 지점 최소 간격",        "m",   LF(padMin), 2, 50},
    {"limEndurance", "완충 비행 가능 시간",          "s",   LF(endurance), 120, 7200},
    {"limReserve",   "착륙 시 남길 배터리",          "%",   LF(battReserve), 5, 60},
};
#undef LF

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
    int sim = -1;                 // -1 unknown, 0 real aircraft, 1 SITL/HITL
    bool staleTold = false;       // link-loss announcements
    bool dlTold = false;
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
    _checkTimer.setSingleShot(true);
    _checkTimer.setInterval(400);
    connect(&_checkTimer, &QTimer::timeout, this, &MLAcactRuntime::_runMissionCheck);

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
    _opMode = s.value(QStringLiteral("opMode"), QStringLiteral("sim")).toString() == QLatin1String("field") ? QStringLiteral("field") : QStringLiteral("sim");
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
        m[QStringLiteral("label")] = tr(d.label);
        m[QStringLiteral("group")] = tr(d.group);
        m[QStringLiteral("unit")] = QString::fromUtf8(d.unit);
        m[QStringLiteral("value")] = d.ref(cur);
        m[QStringLiteral("default")] = d.ref(def);
        m[QStringLiteral("min")] = d.lo;
        m[QStringLiteral("max")] = d.hi;
        m[QStringLiteral("changed")] = _paramOverrides.contains(QString::fromLatin1(d.key));
        out.append(m);
    }
    acact::Limits ldef, lcur = _limitsEff();
    for (const LimDef &d : kLimits) {
        QVariantMap m;
        m[QStringLiteral("key")] = QString::fromLatin1(d.key);
        m[QStringLiteral("label")] = tr(d.label);
        m[QStringLiteral("group")] = tr("미션");
        m[QStringLiteral("unit")] = QString::fromUtf8(d.unit);
        m[QStringLiteral("value")] = d.ref(lcur);
        m[QStringLiteral("default")] = d.ref(ldef);
        m[QStringLiteral("min")] = d.lo;
        m[QStringLiteral("max")] = d.hi;
        m[QStringLiteral("changed")] = _paramOverrides.contains(QString::fromLatin1(d.key));
        out.append(m);
    }
    return out;
}

acact::Limits MLAcactRuntime::_limitsEff() const
{
    acact::Limits l;
    for (const LimDef &d : kLimits) {
        auto it = _paramOverrides.find(QString::fromLatin1(d.key));
        if (it != _paramOverrides.end()) {
            d.ref(l) = std::clamp(it.value(), d.lo, d.hi);
        }
    }
    return l;
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
            _event(QStringLiteral("CFG"), tr("설정 변경: %1 = %2").arg(QString::fromUtf8(d.label)).arg(value));
            emit paramsChanged();
            return;
        }
    }
    for (const LimDef &d : kLimits) {
        if (key == QLatin1String(d.key)) {
            value = std::clamp(value, d.lo, d.hi);
            _paramOverrides[key] = value;
            QSettings().setValue(QStringLiteral("MobilityLab/ACACT/params/") + key, value);
            _event(QStringLiteral("CFG"), tr("설정 변경: %1 = %2").arg(tr(d.label)).arg(value));
            emit paramsChanged();
            _scheduleMissionCheck();
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
    _event(QStringLiteral("CFG"), tr("설정 기본값 복원"));
    emit paramsChanged();
    _scheduleMissionCheck();
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
        _event(QStringLiteral("CFG"), tr("가드 실행 중에는 시연 구역을 바꿀 수 없음"));
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
    _event(QStringLiteral("CFG"), tr("시연 구역: %1, %2 · 방위 %3°").arg(lat, 0, 'f', 7).arg(lon, 0, 'f', 7).arg(bearingDeg, 0, 'f', 0));
    emit siteChanged();
}

void MLAcactRuntime::setSiteFromVehicles(double bearingDeg)
{
    // plan_gen.py --from-vehicles: real homes; bearing auto = mean heading of the vehicles (≤20° apart)
    if (_running) {
        _event(QStringLiteral("CFG"), tr("가드 실행 중에는 시연 구역을 바꿀 수 없음"));
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
            _event(id, tr("위치(홈) 모름 → 시연 구역 설정 불가"));
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
        _event(QStringLiteral("CFG"), tr("제어 가능한 PX4 기체(D1~D4)가 없어 시연 구역을 정할 수 없음"));
        return;
    }
    if (std::isnan(bearingDeg) || bearingDeg < 0) {
        if (hs.isEmpty()) {
            _event(QStringLiteral("CFG"), tr("기수 방향을 아직 모름 → 방위를 직접 입력하세요"));
            return;
        }
        const double mean = std::fmod(std::atan2(sx, cx) * kRadToDeg + 360.0, 360.0);
        double worst = 0;
        for (double h : hs) {
            worst = std::max(worst, std::fabs(std::fmod(h - mean + 540.0, 360.0) - 180.0));
        }
        if (worst > 20.0) {
            _event(QStringLiteral("CFG"), tr("✖ 기체 기수 방향이 서로 %1° 넘게 다릅니다 [%2] — 모든 기체 기수가 비행 방향을 똑같이 보게 놓고 다시")
                                              .arg(worst, 0, 'f', 0).arg(heads.join(QStringLiteral(", "))));
            return;
        }
        bearingDeg = mean;
        _event(QStringLiteral("CFG"), tr("비행 방향(방위) 자동: %1° (기체 기수 방향 평균)").arg(bearingDeg, 0, 'f', 0));
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
            _event(it.key(), tr("※ 위치가 권장 배치와 %1 m 다름 (권장 전방 %2, 우측 %3) — 기체 번호/위치 확인")
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
        _event(QStringLiteral("CFG"), tr("가드 실행 중에는 배치 프로파일을 바꿀 수 없음"));
        emit paramsChanged();
        return;
    }
    _profile = p;
    QSettings().setValue(QStringLiteral("MobilityLab/ACACT/profile"), p);
    _event(QStringLiteral("CFG"), tr("배치 프로파일: %1 — 시연 구역(기체 홈 기준)을 다시 설정하세요").arg(p));
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
        m[QStringLiteral("title")] = tr(si.title.c_str());   // scenario titles are in custom/i18n/en.json
        m[QStringLiteral("available")] = sc.available(si.name);
        out.append(m);
    }
    return out;
}

void MLAcactRuntime::loadScenario(const QString &name, const QString &mode)
{
    if (!_busy.isEmpty()) {
        _event(QStringLiteral("CMD"), tr("진행 중인 작업이 있음: %1").arg(_busy));
        return;
    }
    for (VS *d : _vs_) {
        if (d->connected && (d->inAir || d->armed)) {
            _event(QStringLiteral("CMD"), tr("load 는 모든 기체 지상·시동 꺼짐 상태에서만 가능"));
            return;
        }
    }
    if (!_frame) {
        _event(QStringLiteral("CMD"), tr("시연 구역(중심·방위)을 먼저 설정하세요"));
        return;
    }
    if (mode != QLatin1String("demo") && mode != QLatin1String("rehearsal")) {
        _event(QStringLiteral("CMD"), tr("모드는 demo 또는 rehearsal"));
        return;
    }
    const QStringList ids = _activeIdList();
    if (ids.isEmpty()) {
        _event(QStringLiteral("CMD"), tr("제어 가능한 PX4 기체(D1~D4)가 없음"));
        return;
    }
    for (const QString &id : ids) {
        VS *x = _vs(id);
        if (x && x->v && (!x->v->isInitialConnectComplete() || x->v->missionManager()->inProgress())) {
            _event(id, tr("※ 기체 초기화(파라미터·미션 읽기) 중 — 잠시 후 다시"));
            return;
        }
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
        _event(QStringLiteral("CMD"), tr("시나리오 %1 은(는) 기체 %2대 구성에서 사용할 수 없음").arg(name).arg(ids.size()));
        return;
    }
    _scenario.clear();
    _scenarioMode.clear();
    _event(QStringLiteral("CMD"), tr("시나리오 업로드: %1 / %2 → %3").arg(name, mode, ids.join(QStringLiteral(", "))));
    _uploadNext(ids, name, mode, true);
}

void MLAcactRuntime::_uploadNext(QStringList ids, QString name, QString mode, bool ok)
{
    if (ids.isEmpty()) {
        _busy.clear();
        if (ok) {
            _scenario = name;
            _scenarioMode = mode;
            _event(QStringLiteral("CMD"), tr("시나리오 준비 완료: %1 / %2").arg(name, mode));
        } else {
            _event(QStringLiteral("CMD"), tr("※ 시나리오 업로드 실패 — 기체별 메시지 확인 후 다시 load"));
        }
        runPreflight();
        emit updated();
        return;
    }
    const QString id = ids.takeFirst();
    VS *d = _vs(id);
    if (!d || !d->v || !d->connected) {
        _event(id, tr("※ 업로드 실패: 연결 안 됨"));
        _uploadNext(ids, name, mode, false);
        return;
    }
    _busy = tr("%1 업로드 중 (%2/%3)").arg(id, name, mode);
    emit updated();

    std::vector<std::string> sids;
    for (const QString &x : _activeIdList()) {
        sids.push_back(x.toStdString());
    }
    const Scenarios sc(_effectiveParams(static_cast<int>(sids.size())), sids);
    const auto built = sc.build(name.toStdString(), mode.toStdString());
    auto bit = built.find(id.toStdString());
    if (bit == built.end()) {
        _event(id, tr("※ 업로드 실패: 시나리오에 이 기체 없음"));
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
    std::vector<acact::Fence> fences;
    acact::Fence f;   // plan_gen.py: inclusion circle FENCE_RADIUS around the centre
    f.lat = _frame->lat0();
    f.lon = _frame->lon0();
    f.radius = FENCE_RADIUS;
    fences.push_back(f);
    _writeMission(d, items, fences, [this, ids, name, mode, ok](bool good) {
        QTimer::singleShot(0, this, [this, ids, name, mode, ok, good]() { _uploadNext(ids, name, mode, ok && good); });
    });
}

void MLAcactRuntime::_writeMission(VS *d, QList<MissionItem *> items, const std::vector<acact::Fence> &fences, std::function<void(bool)> done)
{
    // items[0] = planned home. Write, send the fence, read back and compare the count (guard.py download_mission).
    const QString id = d->id;
    const int expect = items.size() - 1;
    QPointer<Vehicle> v = d->v;
    MissionManager *mm = v->missionManager();
    if (mm->inProgress()) {
        qDeleteAll(items);
        _event(id, tr("※ 업로드 실패: 미션 송수신이 진행 중 (잠시 후 다시)"));
        done(false);
        return;
    }
    auto conn = std::make_shared<QMetaObject::Connection>();
    auto timer = std::make_shared<QTimer>();
    timer->setSingleShot(true);
    auto finish = [this, conn, timer, done, id](bool good) {
        QObject::disconnect(*conn);
        timer->stop();
        _missionWriting.remove(id);
        done(good);
        _scheduleMissionCheck();
    };
    connect(timer.get(), &QTimer::timeout, this, [this, id, finish]() {
        _event(id, tr("※ 업로드 실패: 30초 안에 끝나지 않음"));
        finish(false);
    });
    *conn = connect(mm, &PlanManager::sendComplete, this, [this, v, id, expect, finish, conn, fences](bool error) {
        QObject::disconnect(*conn);
        if (error || !v) {
            _event(id, tr("※ 업로드 실패 (기체 거부/통신)"));
            finish(false);
            return;
        }
        // geofence (empty list clears an old one); failure does not fail the mission
        if (v->geoFenceManager()->supported()) {
            QmlObjectListModel polygons, circles;
            for (const acact::Fence &f : fences) {
                if (f.circle) {
                    circles.append(new QGCFenceCircle(QGeoCoordinate(f.lat, f.lon), f.radius, f.inclusion, &circles));
                } else {
                    auto *pg = new QGCFencePolygon(f.inclusion, &polygons);
                    QList<QGeoCoordinate> path;
                    for (const auto &q : f.poly) {
                        path << QGeoCoordinate(q.first, q.second);
                    }
                    pg->appendVertices(path);
                    polygons.append(pg);
                }
            }
            v->geoFenceManager()->sendToVehicle(QGeoCoordinate(), polygons, circles);
        }
        *conn = connect(v->missionManager(), &PlanManager::newMissionItemsAvailable, this, [this, v, id, expect, finish](bool) {
            const int got = v ? v->missionManager()->missionItems().size() : -1;
            if (got != expect) {
                _event(id, tr("※ 업로드 검증 실패 (%1 != %2)").arg(got).arg(expect));
                finish(false);
            } else {
                _event(id, tr("업로드 OK (%1개)").arg(got));
                finish(true);
            }
        });
        QTimer::singleShot(500, this, [v]() {
            if (v) {
                v->missionManager()->loadFromVehicle();
            }
        });
    });
    _missionWriting.insert(id);
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
    return tr("ACACT 회피 제어: PX4 멀티콥터 (OFFBOARD 속도 제어, PX4 v1.16 SITL 검증). ArduPilot·헬리콥터·고정익 기체는 회피 대상(장애물)으로만 고려하며 제어하지 않습니다.");
}

QString MLAcactRuntime::logDir() const
{
    if (qEnvironmentVariableIsSet("MLGCS_PORTABLE_DIR")) {
        return QDir(qEnvironmentVariable("MLGCS_PORTABLE_DIR")).filePath(QStringLiteral("data/ACACT"));
    }
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
                _event(d->id, tr("GCS 연결 해제 — 위치 불확실 기체로 계속 고려"));
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
    connect(vehicle->parameterManager(), &ParameterManager::parametersReadyChanged, this, [this, d, vehicle](bool ready) {
        if (!ready) {
            return;
        }
        ParameterManager *pm = vehicle->parameterManager();
        auto has = [pm](const char *n) { return pm->parameterExists(ParameterManager::defaultComponentId, QString::fromLatin1(n)); };
        if (has("MAV_SYS_ID")) {
            d->paramSysid = pm->getParameter(ParameterManager::defaultComponentId, QStringLiteral("MAV_SYS_ID"))->rawValue().toInt();
        }
        // simulation: PX4 SITL has the simulator parameters (SIM_*), HITL/SIH-on-hardware sets SYS_HITL; ArduPilot SITL has SIM_*
        const bool hitl = has("SYS_HITL") && pm->getParameter(ParameterManager::defaultComponentId, QStringLiteral("SYS_HITL"))->rawValue().toInt() > 0;
        d->sim = (has("SIM_BAT_DRAIN") || has("SIM_SPEEDUP") || has("SIM_GPS_USED") || hitl) ? 1 : 0;
        _event(d->id, d->sim ? tr("시뮬레이션 기체 (SITL/HITL)") : tr("실기체"));
        emit opModeChanged();
        emit profilesChanged();
    });
    emit scenariosChanged();
    d->supported = vehicle->px4Firmware() && vehicle->multiRotor();
    connect(vehicle, &Vehicle::mavlinkMessageReceived, this, [this, d](const mavlink_message_t &m) { _onMessage(d, m); });
    // user missions: re-check whenever a mission or fence is read from / written to the vehicle
    connect(vehicle->missionManager(), &PlanManager::newMissionItemsAvailable, this, [this, d](bool) {
        if (_running && d->inAir && !_missionWriting.contains(d->id)) {
            _event(d->id, tr("※ 비행 중 미션 변경 감지 → 다시 검사"));
        }
        if (!_missionWriting.contains(d->id) && !_scenario.isEmpty() && !_running) {
            _scenario.clear();   // edited outside the scenario loader: it is a user mission now
            _scenarioMode.clear();
            emit updated();
        }
        _scheduleMissionCheck();
    });
    connect(vehicle->missionManager(), &PlanManager::sendComplete, this, [this](bool) { _scheduleMissionCheck(); });
    connect(vehicle->geoFenceManager(), &GeoFenceManager::loadComplete, this, [this]() { _scheduleMissionCheck(); });
    connect(vehicle->geoFenceManager(), &GeoFenceManager::sendComplete, this, [this](bool) { _scheduleMissionCheck(); });
    _scheduleMissionCheck();
    connect(vehicle, &Vehicle::firmwareTypeChanged, this, [d, vehicle]() { d->supported = vehicle->px4Firmware() && vehicle->multiRotor(); });
    connect(vehicle, &Vehicle::vehicleTypeChanged, this, [d, vehicle]() { d->supported = vehicle->px4Firmware() && vehicle->multiRotor(); });
    if (_running) {
        if (_core && !_core->own.count(d->id.toStdString())) {
            _core->own[d->id.toStdString()] = Own{};
        }
        _event(d->id, tr("연결됨 (MAVLink %1, %2)").arg(d->sysid).arg(d->supported ? tr("가드 제어 가능") : tr("장애물로만 고려")));
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
                    _event(d->id, tr("모드 → %1").arg(mode));
                }
                if ((mode == QLatin1String("RTL") || mode == QLatin1String("LAND")) && d->inAir && _auto) {
                    _auto = false;
                    _event(QStringLiteral("AUTO"), tr("%1 비상 귀환/착륙(%2) — 자동 진행 정지. 확인 후 자동 진행 켜기 또는 '대기 기체만 출발'").arg(d->id, mode));
                }
                if (mode == QLatin1String("MANUAL") && d->inAir) {
                    _event(d->id, tr("※ 조종기 수동 개입 감지 — 가드는 이 기체를 피하기만 함"));
                    if (_auto) {
                        _auto = false;
                        _event(QStringLiteral("AUTO"), tr("수동 개입으로 자동 진행 정지 — 상황 정리 후 자동 진행 켜기"));
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
        _event(d->id, tr("조종기 개입 중 → 가드 회피 명령 취소"));
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
    _event(d->id, tr("회피 개입 (Offboard)"));
}

void MLAcactRuntime::_release(VS *d)
{
    if (d->mode != QLatin1String("OFFBOARD")) {   // the pilot or PX4 already took it: do not send it back to the mission
        d->sp[0] = d->sp[1] = d->sp[2] = 0;
        return;
    }
    _startMission(d);
    d->sp[0] = d->sp[1] = d->sp[2] = 0;
    _event(d->id, tr("회피 완료 → 미션 복귀"));
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
        _event(QStringLiteral("SYS"), tr("연결된 기체가 없어 가드를 시작할 수 없음"));
        return false;
    }
    if (!opModeProblem().isEmpty()) {
        _event(QStringLiteral("SYS"), tr("※ 가드 시작 불가: %1").arg(opModeProblem()));
        return false;
    }
    _rebuildCore();
    _flightAirborne = false;
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
    _metaPath = QDir(logDir()).filePath(QStringLiteral("guard_%1_meta.json").arg(stamp));
    _startedAt = QDateTime::currentDateTime();
    _evFile.setFileName(QDir(logDir()).filePath(QStringLiteral("guard_%1_events.csv").arg(stamp)));
    if (_evFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        _evFile.write("t,who,event\n");
    }

    _running = true;
    _seen = true;
    QStringList list;
    for (VS *d : _vs_) {
        list << QStringLiteral("%1%2").arg(d->id, d->supported ? QString() : tr("(장애물)"));
    }
    _event(QStringLiteral("SYS"), tr("ACACT 가드 시작 — %1 · 로그 %2").arg(list.join(QStringLiteral(", ")), _logPath));
    if (!_frame) {
        _event(QStringLiteral("SYS"), tr("시연 구역 미설정 → 첫 기체 위치를 원점으로 사용 (방위 0°)"));
    }
    runPreflight();
    _writeMeta(false);
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
            _event(d->id, tr("종료: 가드 개입 중이던 기체 HOLD"));
        }
    }
    _timer.stop();
    _running = false;
    _writeSummary();
    _writeMeta(true);
    _event(QStringLiteral("SYS"), tr("ACACT 가드 종료 — 요약 %1").arg(_sumPath));
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
        _event(QStringLiteral("CMD"), tr("전 기체 HOLD"));
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
    _event(QStringLiteral("CMD"), tr("전 기체 HOLD (가드 일시정지) — '재개'로 미션 재개"));
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
            _event(QStringLiteral("CMD"), tr("HOLD 재전송: %1").arg(again.join(QStringLiteral(", "))));
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
    _event(QStringLiteral("CMD"), tr("HOLD 기체 미션 재개, 가드 활성"));
    emit updated();
}

void MLAcactRuntime::setAutoMode(bool on)
{
    if (_auto == on) {
        return;
    }
    _auto = on;
    QSettings().setValue(QStringLiteral("MobilityLab/ACACT/auto"), on);
    _event(QStringLiteral("CMD"), tr("자동 진행 %1 (대기 %2초, 착륙 %3)")
                                      .arg(on ? tr("켜짐") : tr("꺼짐"))
                                      .arg(_cfg().autoSyncDelay, 0, 'f', 0)
                                      .arg(_cfg().autoLand ? tr("자동") : tr("수동")));
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
        _event(QStringLiteral("CMD"), tr("가드 일시정지(HOLD) 상태 — '재개' 후 '다음 단계'"));
        return;
    }
    QList<VS *> ready, notReady;
    bool landing = false;
    _syncState(ready, notReady, landing);
    if (ready.isEmpty()) {
        _event(QStringLiteral("CMD"), tr("동기 대기(LOITER_UNLIM) 중인 기체 없음"));
        return;
    }
    if (!notReady.isEmpty() && !force) {
        QStringList ids;
        for (VS *d : notReady) ids << d->id;
        _event(QStringLiteral("CMD"), tr("대기 미도달: %1 → 기다리거나 '대기 기체만 출발'").arg(ids.join(QStringLiteral(", "))));
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
                _event(id, tr("※ 다음 항목 전환 실패: %1 — 상태 확인, 필요 시 '대기 기체만 출발' 또는 개별 조작").arg(err));
            }
            if (--(*remaining) == 0) {
                for (const QString &rid : ids) {
                    VS *x = _vs(rid);
                    if (x && x->mode == QLatin1String("HOLD")) {
                        _startMission(x);
                    }
                }
                _event(QStringLiteral("CMD"), tr("동기 출발: %1").arg(ids.join(QStringLiteral(", "))));
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
            done(false, tr("기체 없음"));
            return;
        }
        if (tryNo >= SET_CURRENT_TRIES) {
            done(false, tr("PX4 가 미션 순서 %1 로 바뀌지 않음 (현재 %2, %3회 송신)").arg(k).arg(x->cur).arg(SET_CURRENT_TRIES));
            return;
        }
        _setCurrent(x, k);
        const double tEnd = _now() + SET_CURRENT_WAIT;
        auto poll = std::make_shared<std::function<void()>>();
        *poll = [this, id, k, cur0, tEnd, tryNo, done, attempt, poll]() {
            VS *y = _vs(id);
            if (!y) {
                done(false, tr("기체 없음"));
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
        done(false, tr("기체 MAVLink ID 모름 → 미션 순서 변경 불가"));
        return;
    }
    (*attempt)(0);
}

void MLAcactRuntime::_gotoNextItem(VS *d, std::function<void(bool, QString)> done)
{
    if (!d->v) {
        done(false, tr("기체 없음"));
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
        done(false, tr("다음 위치 항목 없음 (현재 %1)").arg(d->cur));
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
            _event(QStringLiteral("AUTO"), tr("%1대 이륙지점 상공 도착 — 착륙은 확인 후 '다음 단계'").arg(ready.size()));
        }
        return;
    }
    if (_autoSince < 0) {
        _autoSince = t;
        if (_autoToldAt != _lastSyncT) {
            _autoToldAt = _lastSyncT;
            _event(QStringLiteral("AUTO"), tr("%1대 도착 — %2초 후 %3 (멈추려면 전체 HOLD)")
                                               .arg(ready.size()).arg(_core->config().autoSyncDelay, 0, 'f', 0)
                                               .arg(landing ? tr("착륙") : tr("다음 기동")));
        }
    } else if (t - _autoSince >= _core->config().autoSyncDelay) {
        _autoSince = -1;
        _lastSyncT = t;
        sync(false);
    }
}

QVariantList MLAcactRuntime::runPreflight()
{
    validateMissions();
    _preflightV.clear();
    for (VS *d : _vs_) {
        QStringList msg;
        if (!d->connected) msg << tr("연결 안 됨");
        if (!d->supported) msg << tr("PX4 멀티콥터 아님 — 가드는 장애물로만 고려");
        if (d->gpsFix > 0 && d->gpsFix < 3) msg << QStringLiteral("GPS fix %1").arg(d->gpsFix);
        if (d->sats > 0 && d->sats < 10) msg << tr("위성 %1개").arg(d->sats);
        if (!std::isnan(d->batt) && d->batt < 80) msg << tr("배터리 %1%").arg(d->batt, 0, 'f', 0);
        if (d->paramSysid >= 0 && d->paramSysid != d->sysid) {
            msg << tr("MAV_SYS_ID=%1 (기대 %2) — 모뎀/포트가 바뀌었을 수 있음").arg(d->paramSysid).arg(d->sysid);
        }
        if (_frame && d->attSeen && !d->inAir && d->supported) {
            const double diff = std::fabs(std::fmod(d->yaw - _frame->bearingDeg() + 540.0, 360.0) - 180.0);
            if (diff > 30.0) {
                msg << tr("기수 방향 %1° 가 설정 방위 %2° 와 %3° 다름 — 방위를 잘못 넣었거나 기체 방향이 틀림")
                           .arg(std::fmod(d->yaw + 360.0, 360.0), 0, 'f', 0).arg(_frame->bearingDeg(), 0, 'f', 0).arg(diff, 0, 'f', 0);
            }
        }
        if (d->rcOk == 0) {
            msg << tr("조종기 신호 없음 — 조종기 전원·바인딩 확인 (수동 개입 불가)");
        }
        if (_frame && d->supported && !std::isnan(d->lat) && _siteHomes.contains(d->id)) {
            const auto hp = _siteHomes.value(d->id);
            const auto p0 = _frame->llToFr(hp.first, hp.second);
            const auto p1 = _frame->llToFr(d->lat, d->lon);
            const double dist = std::hypot(p1[0] - p0[0], p1[1] - p0[1]);
            if (dist > 3.0) {
                msg << tr("이륙 위치가 계획과 %1 m 다름").arg(dist, 0, 'f', 1);
            }
        }
        if (d->supported) {
            msg << _missionErrors(d->id);   // user-mission check (errors only; warnings are shown in the mission tab)
        }
        const QList<MissionItem *> items = d->v ? d->v->missionManager()->missionItems() : QList<MissionItem *>();
        if (items.isEmpty()) {
            msg << tr("미션 없음");
        } else if (!std::isnan(d->lat) && !d->inAir && _frame) {
            for (const MissionItem *it : items) {
                if (NAV_POS_CMDS.contains(static_cast<int>(it->command())) && (it->param5() != 0 || it->param6() != 0)) {
                    const auto p0 = _frame->llToFr(it->param5(), it->param6());
                    const auto p1 = _frame->llToFr(d->lat, d->lon);
                    const double dist = std::hypot(p1[0] - p0[0], p1[1] - p0[1]);
                    if (dist > 5.0) {
                        msg << tr("미션 이륙점이 현재 위치와 %1 m 다름 — 다른 기체 미션일 수 있음!").arg(dist, 0, 'f', 0);
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
        _event(QStringLiteral("CMD"), tr("가드를 먼저 시작하세요"));
        return false;
    }
    if (!_core->enabled) {
        _event(QStringLiteral("CMD"), tr("가드 일시정지 상태 — '재개' 후 다시"));
        return false;
    }
    for (VS *d : _vs_) {
        if (d->connected && d->inAir) {
            _event(QStringLiteral("CMD"), tr("이미 비행 중인 기체가 있음 → 일괄 시작 불가 (기체별로 시작)"));
            return false;
        }
    }
    if (!opModeProblem().isEmpty()) {
        _event(QStringLiteral("CMD"), tr("※ 일괄 시작 불가: %1").arg(opModeProblem()));
        return false;
    }
    if (_opMode == QLatin1String("field") && !planSimVerified()) {
        if (!_allowUnverified) {
            _event(QStringLiteral("CMD"), tr("※ 실비행 모드: '%1' 은(는) SITL 비행 기록이 없음 → 시작 거부 (먼저 시뮬레이션으로 같은 계획을 끝까지 비행)").arg(planTitle()));
            return false;
        }
        _event(QStringLiteral("CMD"), tr("※ 운용자 확인: SITL 기록 없이 실비행 시작 — '%1'").arg(planTitle()));
    }
    _allowUnverified = false;
    _flightSig = planSignature();
    _flightTitle = planTitle();
    bool ok = true;
    for (const QVariant &p : runPreflight()) {
        const QVariantMap m = p.toMap();
        if (!m.value(QStringLiteral("ok")).toBool()) {
            ok = false;
            _event(m.value(QStringLiteral("id")).toString(), tr("사전 점검: %1").arg(m.value(QStringLiteral("issues")).toStringList().join(QStringLiteral(" / "))));
        }
    }
    if (!ok) {
        _event(QStringLiteral("CMD"), tr("사전 점검 실패 → 시작 취소"));
        return false;
    }
    // highest layer (last id) first, 5 s apart
    _startQueue.clear();
    for (int i = _vs_.size() - 1; i >= 0; i--) {
        if (_vs_[i]->supported && _vs_[i]->connected) {
            _startQueue.append(_vs_[i]->id);
        }
    }
    _event(QStringLiteral("CMD"), tr("일괄 시작: %1 (5초 간격)").arg(_startQueue.join(QStringLiteral(" → "))));
    _startNext();
    emit updated();
    return true;
}

void MLAcactRuntime::abortStart()
{
    if (!_startQueue.isEmpty()) {
        _startQueue.clear();
        _startTimer.stop();
        _event(QStringLiteral("CMD"), tr("일괄 시작 중단"));
        emit updated();
    }
}

void MLAcactRuntime::_startNext()
{
    if (_startQueue.isEmpty()) {
        return;
    }
    if (!_running || !_core->enabled) {
        _event(QStringLiteral("CMD"), tr("일괄 시작 중단됨 (HOLD/종료)"));
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
            _event(d->id, tr("※ 시동 실패 → 나머지 기체 시작 중단"));
            _startQueue.clear();
            _startTimer.stop();
            emit updated();
            return;
        }
        _startMission(d);
        _event(d->id, tr("시동·미션 시작"));
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
        _event(d->id, tr("운용자 명령 '%1' 우선 → 가드 해제 (미션 재개 시 다시 감시)").arg(what));
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
    _flightEndCheck();
    const double t = _now();
    try {
        _autoTick(t);

        // frame: from the site, otherwise the first vehicle with a position (bearing 0)
        if (!_frame) {
            for (VS *d : _vs_) {
                if (!std::isnan(d->lat)) {
                    _frame = std::make_unique<Frame>(d->lat, d->lon, 0.0);
                    _event(QStringLiteral("SYS"), tr("시연 구역 원점 = %1 현재 위치 (방위 0°)").arg(d->id));
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
                _event(d->id, tr("미션 변경 감지 → 다시 받기"));
            }
            if (std::isnan(d->lat) || !_frame) {
                continue;
            }
            const auto fr = _frame->llToFr(d->lat, d->lon);
            const auto vfr = _frame->neToFr(d->vn, d->ve);
            const double age = t - d->tPos;
            // link loss / recovery (announced once each)
            if (d->inAir && age >= _core->config().staleT && !d->staleTold) {
                d->staleTold = true;
                _event(d->id, tr("※ 텔레메트리 두절 — 마지막 위치·속도로 예측해 계속 고려 (추가 여유 %1 m)").arg(_core->config().degradedMargin, 0, 'f', 1));
            }
            if (d->inAir && age >= _core->config().dlLossT && !d->dlTold) {
                d->dlTold = true;
                _event(d->id, tr("※ 데이터링크 상실 %1 s — 회피 중이었다면 PX4 offboard 상실 페일세이프").arg(age, 0, 'f', 1));
            }
            if (age < _core->config().staleT && d->staleTold) {
                _event(d->id, tr("텔레메트리 복구 (최대 공백 %1 s) — 모드 %2").arg(d->maxGap, 0, 'f', 1).arg(d->mode));
                d->staleTold = false;
                d->dlTold = false;
            }
            if (d->inAir) {
                d->maxGap = std::max(d->maxGap, age);
                if (!std::isnan(d->batt) && d->batt < _core->config().battWarn && !d->battWarned) {
                    d->battWarned = true;
                    _event(d->id, tr("※ 배터리 %1% — 이번 기동 후 착륙 권장").arg(d->batt, 0, 'f', 0));
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
                    _event(d->id, tr("Offboard 전환 실패 (모드 %1) → HOLD").arg(d->mode));
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
                    _event(d->id, tr("※ 가드 미관리 Offboard 감지 → 정지·HOLD"));
                    _stopHold(d);
                }
            } else {
                d->orphanSince = -1;
            }
        }

        const std::vector<Command> cmds = _core->step(t, ins);
        for (const Command &c : cmds) {
            if (c.kind == CmdKind::Event) {
                _event(QString::fromStdString(c.id), _coreText(QString::fromStdString(c.text)));
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
        _event(QStringLiteral("SYS"), tr("※ 가드 내부 오류 (%1) → 회피 중 기체 HOLD").arg(QString::fromUtf8(e.what())));
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
    lines << tr("ACACT Guard 결과 요약 (MobilityLab GCS 내장)") << QString(40, QLatin1Char('='));
    lines << tr("기록: %1").arg(_logPath);
    lines << tr("\n[기체 간 최소 거리]  (같은 층 = 고도차 %1 m 이내일 때의 수평거리)").arg(_core->config().vSep, 0, 'f', 0);
    for (const auto &[k, v] : _core->minSep) {
        auto it = _core->min3d.find(k);
        const double v3 = it == _core->min3d.end() ? qQNaN() : it->second;
        lines << tr("  %1-%2: 같은 층 %3 m / 3D %4 m  %5")
                     .arg(QString::fromStdString(k.first), QString::fromStdString(k.second))
                     .arg(v, 5, 'f', 1).arg(v3, 5, 'f', 1).arg(v >= 5.0 ? QStringLiteral("OK") : tr("※ 5 m 미만"));
    }
    lines << tr("\n[가드 개입]");
    for (VS *d : _vs_) {
        const Own &o = _core->own[d->id.toStdString()];
        const double rms = d->xtN ? std::sqrt(d->xtSq / d->xtN) : qQNaN();
        lines << tr("  %1: 개입 %2회, 개입 시간 %3 s, 경로추종 오차 최대 %4 m / RMS %5 m (회피 후 10초 제외)")
                     .arg(d->id).arg(o.takeovers).arg(o.ownedTime, 5, 'f', 1).arg(d->xtMax, 4, 'f', 1).arg(rms, 4, 'f', 1);
    }
    lines << tr("\n[링크 품질]  (수신 공백 < 0.5 s, 전환 지연 < 0.7 s 권장)");
    for (VS *d : _vs_) {
        QString sw = QStringLiteral("-");
        if (!d->switchLat.isEmpty()) {
            double mx = 0, sum = 0;
            for (double x : d->switchLat) { mx = std::max(mx, x); sum += x; }
            sw = tr("%1 s (평균 %2)").arg(mx, 0, 'f', 2).arg(sum / d->switchLat.size(), 0, 'f', 2);
        }
        lines << tr("  %1: 비행 중 최대 수신 공백 %2 s, Offboard 전환 지연 최대 %3").arg(d->id).arg(d->maxGap, 4, 'f', 2).arg(sw);
    }
    if (_tickErrors) {
        lines << tr("\n※ 가드 내부 오류 %1회").arg(_tickErrors);
    }
    QFile f(_sumPath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        f.write(lines.join(QLatin1Char('\n')).toUtf8());
        f.write("\n");
    }
    qCInfo(MLAcactLog).noquote() << lines.join(QLatin1Char('\n'));
}


// ---------------------------------------------------------------------------
// User-defined missions: pre-flight check, .plan files
// ---------------------------------------------------------------------------
namespace {
double paramOr(Vehicle *v, const char *name, double def, double scale = 1.0)
{
    ParameterManager *pm = v->parameterManager();
    if (pm->parametersReady() && pm->parameterExists(ParameterManager::defaultComponentId, QString::fromLatin1(name))) {
        return pm->getParameter(ParameterManager::defaultComponentId, QString::fromLatin1(name))->rawValue().toDouble() * scale;
    }
    return def;
}
} // namespace

QString MLAcactRuntime::_issueText(const acact::Issue &i) const
{
    const QString c = QString::fromStdString(i.code);
    const QString item = i.seq >= 0 ? tr("항목 %1: ").arg(i.seq + 1) : QString();
    const QString o = QString::fromStdString(i.other);
    auto n1 = [](double x) { return QString::number(x, 'f', 1); };
    auto n0 = [](double x) { return QString::number(x, 'f', 0); };
    if (c == QLatin1String("EMPTY")) return tr("미션 없음");
    if (c == QLatin1String("NO_NAV")) return tr("위치 항목이 없는 미션");
    if (c == QLatin1String("NO_TAKEOFF")) return item + tr("첫 위치 항목이 이륙이 아님 (지상에서 시작)");
    if (c == QLatin1String("TAKEOFF_FAR")) return item + tr("이륙점이 기체 위치와 %1 m 다름 (허용 %2 m) — 다른 기체 미션일 수 있음").arg(n1(i.a), n0(i.b));
    if (c == QLatin1String("ALT_HIGH")) return item + tr("고도 %1 m — 최고 %2 m 초과").arg(n1(i.a), n0(i.b));
    if (c == QLatin1String("ALT_LOW")) return item + tr("고도 %1 m — 최저 순항 %2 m 미만").arg(n1(i.a), n0(i.b));
    if (c == QLatin1String("RANGE")) return item + tr("홈에서 %1 m — 최대 %2 m 초과").arg(n0(i.a), n0(i.b));
    if (c == QLatin1String("FENCE_OUT")) return item + tr("지오펜스(허용 구역) 밖으로 나감");
    if (c == QLatin1String("FENCE_IN")) return item + tr("지오펜스(금지 구역) 안으로 들어감");
    if (c == QLatin1String("ALT_AMSL")) return item + tr("해발 고도 기준 항목 — 홈 해발 %1 m 로 환산해 검사").arg(n1(i.a));
    if (c == QLatin1String("ALT_TERRAIN")) return item + tr("지형 기준 고도 — 고도 검사 생략");
    if (c == QLatin1String("NO_END")) return tr("마지막에 착륙/RTL 없음 — 마지막 지점에서 대기");
    if (c == QLatin1String("JUMP")) return item + tr("DO_JUMP 반복 — 시간 예측은 1회 기준");
    if (c == QLatin1String("SYNC")) return tr("대기점(LOITER_UNLIM) %1개 — 가드 동기 진행 대상").arg(n0(i.a));
    if (c == QLatin1String("ENDURANCE")) return tr("예상 비행 시간이 배터리 %1% 필요 — 사용 가능 %2% 초과").arg(n0(i.a), n0(i.b));
    if (c == QLatin1String("BATT")) return tr("배터리 %1% 필요, 현재 %2% — 착륙 시 %3% 미만").arg(n0(i.a), n0(i.b), n0(i.c));
    if (c == QLatin1String("NOT_CONNECTED")) return tr("연결 끊김 — 마지막으로 받은 미션으로 검사");
    if (c == QLatin1String("PATH_NEAR")) return tr("%1 경로와 %2 m 까지 접근 (고도차 %3 m) — ACACT 회피 예상").arg(o, n1(i.a), n1(i.b));
    if (c == QLatin1String("PATH_NEAR_UNGUARDED")) return tr("%1 경로와 %2 m 까지 접근 — 두 기체 모두 가드가 제어할 수 없음").arg(o, n1(i.a));
    if (c == QLatin1String("TIMED_NEAR")) return tr("동시 출발 시 %1 초 뒤 %2 와 %3 m — 회피 개입 확실").arg(n0(i.b), o, n1(i.a));
    if (c == QLatin1String("PAD_NEAR")) return tr("%1 와 이착륙 지점 간격 %2 m (최소 %3 m) — 저고도에서는 가드가 개입하지 않음").arg(o, n1(i.a), n0(i.b));
    if (c == QLatin1String("SAME_MISSION")) return tr("%1 와 같은 미션 — 기체별 미션을 확인").arg(o);
    return c;
}

void MLAcactRuntime::_runMissionCheck()
{
    std::vector<acact::VehicleMission> vms;
    QList<VS *> order;
    for (VS *d : _vs_) {
        if (!d->v) {
            continue;
        }
        Vehicle *v = d->v;
        acact::VehicleMission vm;
        vm.id = d->id.toStdString();
        vm.controlled = d->supported;
        vm.connected = d->connected;
        vm.lat = d->lat;
        vm.lon = d->lon;
        vm.relAlt = d->relAlt;
        vm.inAir = d->inAir;
        const QGeoCoordinate h = v->homePosition();
        vm.homeValid = h.isValid();
        if (vm.homeValid) {
            vm.homeLat = h.latitude();
            vm.homeLon = h.longitude();
            vm.homeAmsl = std::isnan(h.altitude()) ? 0.0 : h.altitude();
        }
        vm.batt = std::isnan(d->batt) ? -1.0 : d->batt;
        vm.cruise = v->px4Firmware() ? paramOr(v, "MPC_XY_CRUISE", 5.0) : paramOr(v, "WPNAV_SPEED", 5.0, 0.01);
        vm.rtlAlt = v->px4Firmware() ? paramOr(v, "RTL_RETURN_ALT", 30.0) : paramOr(v, "RTL_ALT", 15.0, 0.01);
        vm.endurance = QSettings().value(QStringLiteral("MobilityLab/vehicles/%1/endurance").arg(d->sysid), -1).toDouble();
        for (const MissionItem *mi : v->missionManager()->missionItems()) {
            acact::MItem it;
            it.seq = mi->sequenceNumber();
            it.cmd = static_cast<int>(mi->command());
            it.frame = static_cast<int>(mi->frame());
            it.p1 = mi->param1();
            it.p2 = mi->param2();
            it.p3 = mi->param3();
            it.p4 = mi->param4();
            it.lat = mi->param5();
            it.lon = mi->param6();
            it.alt = mi->param7();
            vm.items.push_back(it);
        }
        if (vm.items.empty() && !d->supported) {
            continue;   // traffic without a mission: nothing to check
        }
        for (const QGCFenceCircle &fc : v->geoFenceManager()->circles()) {
            acact::Fence f;
            f.circle = true;
            f.inclusion = fc.inclusion();
            f.lat = fc.center().latitude();
            f.lon = fc.center().longitude();
            f.radius = const_cast<QGCFenceCircle &>(fc).radius()->rawValue().toDouble();
            vm.fences.push_back(f);
        }
        for (const QGCFencePolygon &fp : v->geoFenceManager()->polygons()) {
            acact::Fence f;
            f.circle = false;
            f.inclusion = fp.inclusion();
            for (const QGeoCoordinate &q : fp.coordinateList()) {
                f.poly.push_back({q.latitude(), q.longitude()});
            }
            vm.fences.push_back(f);
        }
        vms.push_back(vm);
        order << d;
    }
    const acact::Config cfg = _cfg();
    const acact::Limits lim = _limitsEff();
    _report = acact::checkMissions(vms, cfg, lim);

    const double la0 = _report.originLat, lo0 = _report.originLon, c0 = std::cos(la0 * kDegToRad);
    auto toLl = [&](double n, double e) { return QVariantMap{{QStringLiteral("lat"), la0 + n / 111320.0}, {QStringLiteral("lon"), lo0 + e / (111320.0 * c0)}}; };
    auto issues = [this](const std::vector<acact::Issue> &is) {
        QVariantList out;
        for (const acact::Issue &i : is) {
            out.append(QVariantMap{{QStringLiteral("level"), static_cast<int>(i.level)}, {QStringLiteral("code"), QString::fromStdString(i.code)},
                                   {QStringLiteral("seq"), i.seq}, {QStringLiteral("other"), QString::fromStdString(i.other)},
                                   {QStringLiteral("text"), _issueText(i)}});
        }
        return out;
    };
    int nErr = 0, nWarn = 0;
    QVariantList vl;
    QStringList newErrors;
    QSet<QString> errorsNow;
    for (size_t k = 0; k < _report.vehicles.size(); k++) {
        const acact::VehicleReport &r = _report.vehicles[k];
        VS *d = order[static_cast<int>(k)];
        QVariantList path;
        for (size_t p = 0; p < r.path.size(); p += 4) {
            QVariantMap m = toLl(r.path[p].n, r.path[p].e);
            m[QStringLiteral("alt")] = r.path[p].u;
            m[QStringLiteral("t")] = r.path[p].t;
            path.append(m);
        }
        for (const acact::Issue &i : r.issues) {
            nErr += i.level == acact::Level::Error;
            nWarn += i.level == acact::Level::Warn;
            if (i.level == acact::Level::Error && i.code != "EMPTY") {   // no mission yet is normal before loading
                const QString key = d->id + QLatin1Char('|') + _issueText(i);
                errorsNow.insert(key);
                if (!_reportedErrors.contains(key)) {
                    newErrors << key;
                }
            }
        }
        vl.append(QVariantMap{
            {QStringLiteral("id"), d->id}, {QStringLiteral("sysid"), d->sysid}, {QStringLiteral("controlled"), d->supported},
            {QStringLiteral("navItems"), r.navItems}, {QStringLiteral("syncPoints"), r.syncPoints}, {QStringLiteral("length"), r.length},
            {QStringLiteral("duration"), r.duration}, {QStringLiteral("maxAlt"), r.maxAlt}, {QStringLiteral("worst"), static_cast<int>(r.worst())},
            {QStringLiteral("issues"), issues(r.issues)}, {QStringLiteral("path"), path}});
    }
    QVariantList pl;
    for (const acact::PairReport &p : _report.pairs) {
        int worst = 0;
        for (const acact::Issue &i : p.issues) {
            worst = std::max(worst, static_cast<int>(i.level));
            nErr += i.level == acact::Level::Error;
            nWarn += i.level == acact::Level::Warn;
            if (i.level == acact::Level::Error) {
                const QString key = QString::fromStdString(p.a) + QLatin1Char('|') + _issueText(i);
                errorsNow.insert(key);
                if (!_reportedErrors.contains(key)) {
                    newErrors << key;
                }
            }
        }
        QVariantMap m = toLl(p.pathN, p.pathE);
        m[QStringLiteral("a")] = QString::fromStdString(p.a);
        m[QStringLiteral("b")] = QString::fromStdString(p.b);
        m[QStringLiteral("pathMin")] = p.pathMin < 1e8 ? QVariant(p.pathMin) : QVariant();
        m[QStringLiteral("pathDz")] = p.pathDz;
        m[QStringLiteral("timedMin")] = p.timedMin < 1e8 ? QVariant(p.timedMin) : QVariant();
        m[QStringLiteral("timedAt")] = p.timedAt;
        m[QStringLiteral("padMin")] = p.padMin < 1e8 ? QVariant(p.padMin) : QVariant();
        m[QStringLiteral("worst")] = worst;
        m[QStringLiteral("issues")] = issues(p.issues);
        pl.append(m);
    }
    _missionCheckV = {{QStringLiteral("time"), QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"))},
                      {QStringLiteral("ok"), _report.ok()}, {QStringLiteral("errors"), nErr}, {QStringLiteral("warnings"), nWarn},
                      {QStringLiteral("vehicles"), vl}, {QStringLiteral("pairs"), pl}};
    for (const QString &k : newErrors) {
        const int bar = k.indexOf(QLatin1Char('|'));
        _event(k.left(bar), tr("※ 미션 검사: %1").arg(k.mid(bar + 1)));
    }
    _reportedErrors = errorsNow;
    emit missionCheckChanged();
}

QVariantMap MLAcactRuntime::validateMissions()
{
    _checkTimer.stop();
    _runMissionCheck();
    return _missionCheckV;
}

QStringList MLAcactRuntime::_missionErrors(const QString &id) const
{
    QStringList out;
    const std::string sid = id.toStdString();
    for (const acact::VehicleReport &r : _report.vehicles) {
        if (r.id == sid) {
            for (const acact::Issue &i : r.issues) {
                // EMPTY is already the guard.py preflight item "미션 없음" (TAKEOFF_FAR is not: guard.py checks it only with a site)
                if (i.level == acact::Level::Error && i.code != "EMPTY") {
                    out << _issueText(i);
                }
            }
        }
    }
    for (const acact::PairReport &p : _report.pairs) {
        if (p.a != sid && p.b != sid) {
            continue;
        }
        for (acact::Issue i : p.issues) {
            if (i.level == acact::Level::Error) {
                i.other = p.a == sid ? p.b : p.a;
                out << _issueText(i);
            }
        }
    }
    return out;
}

bool MLAcactRuntime::uploadPlanFile(int sysid, const QString &pathIn)
{
    VS *d = _vsBySysid(sysid);
    const QString path = pathIn.startsWith(QLatin1String("file:")) ? QUrl(pathIn).toLocalFile() : pathIn;
    const QString who = d ? d->id : QStringLiteral("D%1").arg(sysid);
    if (!d || !d->v || !d->connected) {
        _event(who, tr("※ 미션 파일 업로드 불가: 기체 연결 안 됨"));
        return false;
    }
    if (_core && _core->own.count(d->id.toStdString()) && _core->own[d->id.toStdString()].owned) {
        _event(who, tr("※ 회피 중에는 미션을 바꿀 수 없음 — 회피가 끝난 뒤 다시"));
        return false;
    }
    if (!d->v->isInitialConnectComplete() || d->v->missionManager()->inProgress()) {
        // QGC is still reading parameters / the mission from the vehicle: a write now would race with that read
        _event(who, tr("※ 기체 초기화(파라미터·미션 읽기) 중 — 잠시 후 다시"));
        return false;
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        _event(who, tr("※ 미션 파일을 열 수 없음: %1").arg(path));
        return false;
    }
    QJsonParseError pe;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll(), &pe).object();
    if (pe.error != QJsonParseError::NoError || root.value(QStringLiteral("fileType")).toString() != QLatin1String("Plan")) {
        _event(who, tr("※ QGC .plan 파일이 아님: %1").arg(QFileInfo(path).fileName()));
        return false;
    }
    const QJsonObject mission = root.value(QStringLiteral("mission")).toObject();
    const QJsonArray home = mission.value(QStringLiteral("plannedHomePosition")).toArray();
    QList<MissionItem *> items;
    items << new MissionItem(0, MAV_CMD_NAV_WAYPOINT, MAV_FRAME_GLOBAL, 0, 0, 0, 0, home.size() > 1 ? home[0].toDouble() : 0.0,
                             home.size() > 1 ? home[1].toDouble() : 0.0, home.size() > 2 ? home[2].toDouble() : 0.0, true, false);
    int seq = 1;
    for (const QJsonValue &jv : mission.value(QStringLiteral("items")).toArray()) {
        const QJsonObject o = jv.toObject();
        if (o.value(QStringLiteral("type")).toString() != QLatin1String("SimpleItem")) {
            qDeleteAll(items);
            _event(who, tr("※ 복합 항목(%1)이 있는 계획은 QGC 계획 화면에서 업로드하세요").arg(o.value(QStringLiteral("complexItemType")).toString()));
            return false;
        }
        const QJsonArray p = o.value(QStringLiteral("params")).toArray();
        auto prm = [&p](int k) { return k < p.size() && !p[k].isNull() ? p[k].toDouble() : qQNaN(); };
        items << new MissionItem(seq++, static_cast<MAV_CMD>(o.value(QStringLiteral("command")).toInt()),
                                 static_cast<MAV_FRAME>(o.value(QStringLiteral("frame")).toInt()), prm(0), prm(1), prm(2), prm(3), prm(4),
                                 prm(5), prm(6), o.value(QStringLiteral("autoContinue")).toBool(true), false);
    }
    if (items.size() < 2) {
        qDeleteAll(items);
        _event(who, tr("※ 미션 항목이 없는 계획 파일"));
        return false;
    }
    std::vector<acact::Fence> fences;
    const QJsonObject gf = root.value(QStringLiteral("geoFence")).toObject();
    for (const QJsonValue &cv : gf.value(QStringLiteral("circles")).toArray()) {
        const QJsonObject co = cv.toObject();
        const QJsonObject circ = co.value(QStringLiteral("circle")).toObject();
        const QJsonArray ctr = circ.value(QStringLiteral("center")).toArray();
        acact::Fence fe;
        fe.circle = true;
        fe.inclusion = co.value(QStringLiteral("inclusion")).toBool(true);
        fe.lat = ctr.size() > 1 ? ctr[0].toDouble() : 0;
        fe.lon = ctr.size() > 1 ? ctr[1].toDouble() : 0;
        fe.radius = circ.value(QStringLiteral("radius")).toDouble();
        fences.push_back(fe);
    }
    for (const QJsonValue &pv : gf.value(QStringLiteral("polygons")).toArray()) {
        const QJsonObject po = pv.toObject();
        acact::Fence fe;
        fe.circle = false;
        fe.inclusion = po.value(QStringLiteral("inclusion")).toBool(true);
        for (const QJsonValue &q : po.value(QStringLiteral("polygon")).toArray()) {
            const QJsonArray ll = q.toArray();
            if (ll.size() > 1) {
                fe.poly.push_back({ll[0].toDouble(), ll[1].toDouble()});
            }
        }
        fences.push_back(fe);
    }
    if (d->inAir) {
        _event(who, tr("※ 비행 중 미션 교체: %1").arg(QFileInfo(path).fileName()));
    }
    _event(who, tr("미션 파일 업로드: %1 (%2개, 지오펜스 %3)").arg(QFileInfo(path).fileName()).arg(items.size() - 1).arg(fences.size()));
    _scenario.clear();
    _scenarioMode.clear();
    _busy = tr("%1 미션 업로드 중").arg(who);
    emit updated();
    _writeMission(d, items, fences, [this, who](bool ok) {
        _busy.clear();
        if (ok) {
            const QVariantMap r = validateMissions();
            _event(who, tr("미션 검사: 오류 %1 · 주의 %2").arg(r.value(QStringLiteral("errors")).toInt()).arg(r.value(QStringLiteral("warnings")).toInt()));
        }
        emit updated();
    });
    return true;
}

bool MLAcactRuntime::savePlanFile(int sysid, const QString &pathIn)
{
    VS *d = _vsBySysid(sysid);
    QString path = pathIn.startsWith(QLatin1String("file:")) ? QUrl(pathIn).toLocalFile() : pathIn;
    if (!path.endsWith(QLatin1String(".plan"))) {
        path += QStringLiteral(".plan");
    }
    if (!d || !d->v) {
        return false;
    }
    Vehicle *v = d->v;
    QJsonArray items;
    for (const MissionItem *mi : v->missionManager()->missionItems()) {
        QJsonArray p;
        for (double x : {mi->param1(), mi->param2(), mi->param3(), mi->param4(), mi->param5(), mi->param6(), mi->param7()}) {
            p.append(std::isnan(x) ? QJsonValue() : QJsonValue(x));
        }
        QJsonObject o{{QStringLiteral("type"), QStringLiteral("SimpleItem")}, {QStringLiteral("command"), static_cast<int>(mi->command())},
                      {QStringLiteral("frame"), static_cast<int>(mi->frame())}, {QStringLiteral("params"), p},
                      {QStringLiteral("autoContinue"), mi->autoContinue()}, {QStringLiteral("doJumpId"), mi->sequenceNumber() + 1}};
        if (mi->frame() == MAV_FRAME_GLOBAL_RELATIVE_ALT || mi->frame() == MAV_FRAME_GLOBAL) {
            o[QStringLiteral("Altitude")] = mi->param7();
            o[QStringLiteral("AltitudeMode")] = mi->frame() == MAV_FRAME_GLOBAL ? 2 : 1;
            o[QStringLiteral("AMSLAltAboveTerrain")] = QJsonValue();
        }
        items.append(o);
    }
    const QGeoCoordinate h = v->homePosition();
    QJsonArray circles, polygons;
    for (const QGCFenceCircle &fc : v->geoFenceManager()->circles()) {
        circles.append(QJsonObject{{QStringLiteral("circle"), QJsonObject{{QStringLiteral("center"), QJsonArray{fc.center().latitude(), fc.center().longitude()}},
                                                                          {QStringLiteral("radius"), const_cast<QGCFenceCircle &>(fc).radius()->rawValue().toDouble()}}},
                                   {QStringLiteral("inclusion"), fc.inclusion()}, {QStringLiteral("version"), 1}});
    }
    for (const QGCFencePolygon &fp : v->geoFenceManager()->polygons()) {
        QJsonArray pts;
        for (const QGeoCoordinate &q : fp.coordinateList()) {
            pts.append(QJsonArray{q.latitude(), q.longitude()});
        }
        polygons.append(QJsonObject{{QStringLiteral("polygon"), pts}, {QStringLiteral("inclusion"), fp.inclusion()}, {QStringLiteral("version"), 1}});
    }
    const QJsonObject root{
        {QStringLiteral("fileType"), QStringLiteral("Plan")},
        {QStringLiteral("groundStation"), QStringLiteral("MobilityLabGCS")},
        {QStringLiteral("version"), 1},
        {QStringLiteral("mission"), QJsonObject{{QStringLiteral("version"), 2}, {QStringLiteral("firmwareType"), v->px4Firmware() ? 12 : 3},
                                                {QStringLiteral("vehicleType"), static_cast<int>(v->vehicleType())},
                                                {QStringLiteral("cruiseSpeed"), 15}, {QStringLiteral("hoverSpeed"), 5},
                                                {QStringLiteral("globalPlanAltitudeMode"), 1},
                                                {QStringLiteral("plannedHomePosition"), QJsonArray{h.isValid() ? h.latitude() : d->lat, h.isValid() ? h.longitude() : d->lon,
                                                                                                   h.isValid() && !std::isnan(h.altitude()) ? h.altitude() : 0.0}},
                                                {QStringLiteral("items"), items}}},
        {QStringLiteral("geoFence"), QJsonObject{{QStringLiteral("version"), 2}, {QStringLiteral("circles"), circles}, {QStringLiteral("polygons"), polygons}}},
        {QStringLiteral("rallyPoints"), QJsonObject{{QStringLiteral("version"), 2}, {QStringLiteral("points"), QJsonArray()}}},
    };
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        _event(d->id, tr("※ 미션 파일 저장 실패: %1").arg(path));
        return false;
    }
    f.write(QJsonDocument(root).toJson());
    _event(d->id, tr("미션 저장: %1").arg(path));
    return true;
}


// ---------------------------------------------------------------------------
// Real flight vs simulation
// ---------------------------------------------------------------------------
QVariantList MLAcactRuntime::fleetKinds() const
{
    QVariantList out;
    for (const VS *d : _vs_) {
        out.append(QVariantMap{{QStringLiteral("id"), d->id}, {QStringLiteral("sysid"), d->sysid}, {QStringLiteral("sim"), d->sim},
                               {QStringLiteral("supported"), d->supported}, {QStringLiteral("connected"), d->connected}});
    }
    return out;
}

QString MLAcactRuntime::opModeProblem() const
{
    QStringList real, sim;
    for (const VS *d : _vs_) {
        if (!d->connected || !d->supported) {
            continue;
        }
        if (d->sim == 0) {
            real << d->id;
        } else if (d->sim == 1) {
            sim << d->id;
        }
    }
    if (_opMode == QLatin1String("sim") && !real.isEmpty()) {
        return tr("시뮬레이션 모드인데 실기체 연결됨 (%1) — 실비행 모드로 바꾸고 실비행 절차를 따르세요").arg(real.join(QStringLiteral(", ")));
    }
    if (_opMode == QLatin1String("field") && !sim.isEmpty()) {
        return tr("실비행 모드인데 시뮬레이션 기체 연결됨 (%1) — 시뮬레이션 모드로 바꾸세요").arg(sim.join(QStringLiteral(", ")));
    }
    return QString();
}

void MLAcactRuntime::setOpMode(const QString &mode)
{
    const QString m = mode == QLatin1String("field") ? QStringLiteral("field") : QStringLiteral("sim");
    if (m == _opMode) {
        return;
    }
    if (_running) {
        _event(QStringLiteral("CFG"), tr("가드 실행 중에는 운용 모드를 바꿀 수 없음"));
        emit opModeChanged();
        return;
    }
    _opMode = m;
    _allowUnverified = false;
    QSettings().setValue(QStringLiteral("MobilityLab/ACACT/opMode"), m);
    _event(QStringLiteral("CFG"), m == QLatin1String("field") ? tr("운용 모드: 실비행 — SITL 기록이 있는 계획만 일괄 시작")
                                                                : tr("운용 모드: 시뮬레이션"));
    emit opModeChanged();
}

void MLAcactRuntime::allowUnverifiedOnce()
{
    _allowUnverified = true;
    _event(QStringLiteral("CMD"), tr("운용자: 다음 일괄 시작은 SITL 기록 없이 허용 ('%1')").arg(planTitle()));
}

QString MLAcactRuntime::planTitle() const
{
    if (!_scenario.isEmpty()) {
        return QStringLiteral("%1 / %2").arg(_scenario, _scenarioMode == QLatin1String("demo") ? tr("본 시연") : tr("리허설"));
    }
    QStringList ids;
    for (const VS *d : _vs_) {
        if (d->supported && d->v && !d->v->missionManager()->missionItems().isEmpty()) {
            ids << d->id;
        }
    }
    return ids.isEmpty() ? tr("미션 없음") : tr("사용자 미션 (%1)").arg(ids.join(QStringLiteral(", ")));
}

QString MLAcactRuntime::planSignature() const
{
    // scenario: geometry is relative to the site → the same scenario/mode/layout/fleet anywhere.
    // user missions: the exact items (absolute positions) of every controlled vehicle.
    if (!_scenario.isEmpty()) {
        return QStringLiteral("SC|%1|%2|%3|%4").arg(_scenario, _scenarioMode, _profile, _activeIdList().join(QLatin1Char(',')));
    }
    QByteArray b;
    for (const VS *d : _vs_) {
        if (!d->supported || !d->v) {
            continue;
        }
        const auto &items = d->v->missionManager()->missionItems();
        if (items.isEmpty()) {
            continue;
        }
        b += d->id.toUtf8() + ':';
        for (const MissionItem *mi : items) {
            b += QByteArray::number(static_cast<int>(mi->command())) + ',' + QByteArray::number(qRound64(mi->param5() * 1e6)) + ',' +
                 QByteArray::number(qRound64(mi->param6() * 1e6)) + ',' + QByteArray::number(qRound64(mi->param7() * 10)) + ';';
        }
    }
    if (b.isEmpty()) {
        return QString();
    }
    return QStringLiteral("MS|") + QString::fromLatin1(QCryptographicHash::hash(b, QCryptographicHash::Sha1).toHex().left(16));
}

QVariantList MLAcactRuntime::simRecords() const
{
    return QSettings().value(QStringLiteral("MobilityLab/ACACT/simRecords")).toList();
}

bool MLAcactRuntime::planSimVerified() const
{
    const QString sig = planSignature();
    if (sig.isEmpty()) {
        return false;
    }
    for (const QVariant &r : simRecords()) {
        if (r.toMap().value(QStringLiteral("sig")).toString() == sig) {
            return true;
        }
    }
    return false;
}

void MLAcactRuntime::_flightEndCheck()
{
    bool anyAir = false, anyArmed = false, allSim = true, any = false;
    for (const VS *d : _vs_) {
        if (!d->supported || !d->connected) {
            continue;
        }
        any = true;
        anyAir = anyAir || d->inAir;
        anyArmed = anyArmed || d->armed;
        allSim = allSim && d->sim == 1;
    }
    if (anyAir) {
        _flightAirborne = true;
        return;
    }
    if (!_flightAirborne || anyArmed || !any) {
        return;
    }
    _flightAirborne = false;
    if (_opMode != QLatin1String("sim") || !allSim || _flightSig.isEmpty()) {
        return;
    }
    double minSep = 1e9;
    int takeovers = 0;
    if (_core) {
        for (const auto &kv : _core->minSep) {
            minSep = std::min(minSep, kv.second);
        }
        for (const auto &kv : _core->own) {
            takeovers += kv.second.takeovers;
        }
    }
    const double dEmerg = _cfg().dEmerg;
    if (_tickErrors > 0 || (minSep < 1e8 && minSep < dEmerg)) {
        _event(QStringLiteral("SYS"), tr("※ SITL 비행 종료 — 최소 이격 %1 m / 내부 오류 %2 → 검증 기록으로 남기지 않음")
                                          .arg(minSep < 1e8 ? minSep : 0.0, 0, 'f', 1).arg(_tickErrors));
        return;
    }
    QVariantList recs = simRecords();
    recs.prepend(QVariantMap{{QStringLiteral("sig"), _flightSig}, {QStringLiteral("title"), _flightTitle},
                             {QStringLiteral("date"), QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm"))},
                             {QStringLiteral("minSep"), minSep < 1e8 ? QVariant(minSep) : QVariant()}, {QStringLiteral("takeovers"), takeovers}});
    while (recs.size() > 50) {
        recs.removeLast();
    }
    QSettings().setValue(QStringLiteral("MobilityLab/ACACT/simRecords"), recs);
    _event(QStringLiteral("SYS"), tr("SITL 검증 기록: '%1' — 착륙 완료, 최소 이격 %2 m, 개입 %3회")
                                      .arg(_flightTitle).arg(minSep < 1e8 ? QString::number(minSep, 'f', 1) : QStringLiteral("—")).arg(takeovers));
    emit opModeChanged();
    emit missionCheckChanged();
}


void MLAcactRuntime::_writeMeta(bool final)
{
    // guard_<stamp>_meta.json: what MLFlightAnalysis needs besides the CSV (site, vehicles, thresholds, plan, mode)
    if (_metaPath.isEmpty() || !_core) {
        return;
    }
    const acact::Config c = _core->config();
    QJsonArray vehicles;
    for (const VS *d : _vs_) {
        vehicles.append(QJsonObject{{QStringLiteral("id"), d->id}, {QStringLiteral("sysid"), d->sysid}, {QStringLiteral("supported"), d->supported},
                                    {QStringLiteral("sim"), d->sim},
                                    {QStringLiteral("firmware"), d->v ? (d->v->px4Firmware() ? QStringLiteral("PX4") : (d->v->apmFirmware() ? QStringLiteral("ArduPilot") : QStringLiteral("other"))) : QString()}});
    }
    QJsonObject m{
        {QStringLiteral("version"), 1},
        {QStringLiteral("app"), QStringLiteral("%1 (QGC %2)").arg(QStringLiteral(ML_GCS_VERSION), QCoreApplication::applicationVersion())},
        {QStringLiteral("start"), _startedAt.toString(Qt::ISODate)},
        {QStringLiteral("opMode"), _opMode},
        {QStringLiteral("plan"), planTitle()},
        {QStringLiteral("planSignature"), planSignature()},
        {QStringLiteral("profile"), _profile},
        {QStringLiteral("vehicles"), vehicles},
        {QStringLiteral("cfg"), QJsonObject{{QStringLiteral("dSafe"), c.dSafe}, {QStringLiteral("dEmerg"), c.dEmerg}, {QStringLiteral("vSep"), c.vSep},
                                            {QStringLiteral("tLook"), c.tLook}, {QStringLiteral("staleT"), c.staleT}, {QStringLiteral("rs"), c.acact.rs},
                                            {QStringLiteral("maxHSpeed"), c.maxHSpeed}}},
    };
    if (_frame) {
        m[QStringLiteral("site")] = QJsonObject{{QStringLiteral("lat"), _frame->lat0()}, {QStringLiteral("lon"), _frame->lon0()},
                                                {QStringLiteral("bearing"), _frame->bearingDeg()}};
    }
    if (final) {
        double minSep = 1e9;
        int takeovers = 0;
        for (const auto &kv : _core->minSep) {
            minSep = std::min(minSep, kv.second);
        }
        for (const auto &kv : _core->own) {
            takeovers += kv.second.takeovers;
        }
        m[QStringLiteral("end")] = QDateTime::currentDateTime().toString(Qt::ISODate);
        m[QStringLiteral("duration")] = _startedAt.secsTo(QDateTime::currentDateTime());
        m[QStringLiteral("minSep")] = minSep < 1e8 ? QJsonValue(minSep) : QJsonValue();
        m[QStringLiteral("takeovers")] = takeovers;
        m[QStringLiteral("tickErrors")] = _tickErrors;
    }
    QFile f(_metaPath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(m).toJson());
    }
}


QString MLAcactRuntime::_coreText(const QString &ko) const
{
    // The engine keeps the original Korean event texts (core.py); shown in English when the UI is English.
    if (tr("회피") == QStringLiteral("회피")) {
        return ko;
    }
    static const QList<QPair<QRegularExpression, QString>> table = {
        {QRegularExpression(QStringLiteral("^통신 두절 (\\d+)초 — RTL 귀환 중으로 간주, 충돌 판단에서 제외 \\(육안 확인!\\)$")),
         QStringLiteral("link lost for \\1 s — assumed returning (RTL), left out of conflict checks (check visually!)")},
        {QRegularExpression(QStringLiteral("^위험 근접 ([\\d.]+)m — 두 기체 모두 개입 불가 \\(모드 (\\S+)/(\\S+)\\)$")),
         QStringLiteral("danger: \\1 m — the guard can fly neither vehicle (modes \\2/\\3)")},
        {QRegularExpression(QStringLiteral("^모드 (\\S+) 전환 감지 → 가드 해제 \\(미션 재개 시 다시 감시\\)$")),
         QStringLiteral("mode \\1 detected → guard releases (watches again when the mission resumes)")},
        {QRegularExpression(QStringLiteral("^텔레메트리 끊김 — PX4 offboard 상실 페일세이프로 전환 예상$")),
         QStringLiteral("telemetry lost — PX4 offboard-loss failsafe expected")},
    };
    for (const auto &[re, en] : table) {
        const QRegularExpressionMatch m = re.match(ko);
        if (m.hasMatch()) {
            QString out = en;
            for (int k = m.lastCapturedIndex(); k >= 1; k--) {
                out.replace(QStringLiteral("\\%1").arg(k), m.captured(k));
            }
            return out;
        }
    }
    return ko;
}


// ---------------------------------------------------------------------------
// Per-vehicle profiles (QSettings MobilityLab/vehicles/<sysid>/…)
// ---------------------------------------------------------------------------
QVariantList MLAcactRuntime::vehicleProfiles() const
{
    QSettings s;
    s.beginGroup(QStringLiteral("MobilityLab/vehicles"));
    QSet<int> ids;
    for (const QString &g : s.childGroups()) {
        ids.insert(g.toInt());
    }
    for (const VS *d : _vs_) {
        ids.insert(d->sysid);
    }
    QList<int> sorted(ids.begin(), ids.end());
    std::sort(sorted.begin(), sorted.end());
    QVariantList out;
    for (int id : sorted) {
        if (id <= 0) {
            continue;
        }
        const VS *d = nullptr;
        for (const VS *x : _vs_) {
            if (x->sysid == id) {
                d = x;
            }
        }
        QString autoType;
        if (d && d->v) {
            autoType = d->v->multiRotor() ? tr("멀티콥터") : (d->v->fixedWing() ? tr("고정익") : (d->v->vtol() ? QStringLiteral("VTOL") : tr("헬기·기타")));
            autoType += d->v->px4Firmware() ? QStringLiteral(" · PX4") : (d->v->apmFirmware() ? QStringLiteral(" · ArduPilot") : QString());
        }
        s.beginGroup(QString::number(id));
        out.append(QVariantMap{{QStringLiteral("sysid"), id}, {QStringLiteral("id"), QStringLiteral("D%1").arg(id)},
                               {QStringLiteral("connected"), d && d->connected}, {QStringLiteral("autoType"), autoType},
                               {QStringLiteral("sim"), d ? d->sim : -1}, {QStringLiteral("supported"), d && d->supported},
                               {QStringLiteral("name"), s.value(QStringLiteral("name")).toString()},
                               {QStringLiteral("link"), s.value(QStringLiteral("link")).toString()},
                               {QStringLiteral("endurance"), s.value(QStringLiteral("endurance"), -1).toDouble()},
                               {QStringLiteral("notes"), s.value(QStringLiteral("notes")).toString()}});
        s.endGroup();
    }
    return out;
}

void MLAcactRuntime::setVehicleProfile(int sysid, const QString &key, const QVariant &value)
{
    static const QStringList keys = {QStringLiteral("name"), QStringLiteral("link"), QStringLiteral("endurance"), QStringLiteral("notes")};
    if (sysid <= 0 || !keys.contains(key)) {
        return;
    }
    QSettings().setValue(QStringLiteral("MobilityLab/vehicles/%1/%2").arg(sysid).arg(key), value);
    emit profilesChanged();
    if (key == QLatin1String("endurance")) {
        _scheduleMissionCheck();
    }
}

QString MLAcactRuntime::vehicleName(int sysid) const
{
    const QString n = QSettings().value(QStringLiteral("MobilityLab/vehicles/%1/name").arg(sysid)).toString();
    return n.isEmpty() ? QStringLiteral("D%1").arg(sysid) : QStringLiteral("D%1 %2").arg(sysid).arg(n);
}
