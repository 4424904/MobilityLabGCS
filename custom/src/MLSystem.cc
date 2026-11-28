#include "MLSystem.h"

#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "Vehicle.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QProcess>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtCore/QSysInfo>
#include <QtCore/QTextStream>
#include <QtCore/QTimer>
#include <QtCore/QUrl>
#include <QtGui/QGuiApplication>
#include <QtGui/QScreen>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>

#ifndef ML_GCS_VERSION
#define ML_GCS_VERSION "dev"
#endif

namespace {
const char *kRepo = "4424904/MobilityLabGCS";
QString lockPath()
{
    const QString d = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(d);
    return QDir(d).filePath(QStringLiteral("mlgcs-session.lock"));
}
// keys whose values must never leave the PC in a diagnostic report
bool secretKey(const QString &k)
{
    const QString l = k.toLower();
    return l.contains(QLatin1String("key")) || l.contains(QLatin1String("token")) || l.contains(QLatin1String("password")) || l.contains(QLatin1String("secret"))
        || l.contains(QLatin1String("lat")) || l.contains(QLatin1String("lon")) || l.contains(QLatin1String("favorites")) || l.contains(QLatin1String("coordinate"))
        || l.contains(QLatin1String("position"));
}
} // namespace

MLSystem::MLSystem(QObject *parent)
    : QObject(parent)
{
    // abnormal-exit detection: the lock file survives only if the previous run did not quit normally
    QFile lock(lockPath());
    _prevCrash = lock.exists();
    if (lock.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        lock.write(QDateTime::currentDateTime().toString(Qt::ISODate).toUtf8());
    }
    connect(qApp, &QCoreApplication::aboutToQuit, this, &MLSystem::_markClean);
}

MLSystem::~MLSystem() = default;

void MLSystem::_markClean()
{
    QFile::remove(lockPath());
}

QString MLSystem::dataDir() const
{
    return QDir(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)).filePath(QStringLiteral("MobilityLab"));
}

QString MLSystem::backupSettings(const QString &path)
{
    QSettings src;
    src.sync();
    QString p = path;
    if (p.startsWith(QLatin1String("file:"))) p = QUrl(p).toLocalFile();
    if (p.isEmpty()) {
        QDir().mkpath(dataDir());
        p = QDir(dataDir()).filePath(QStringLiteral("MobilityLabGCS-settings-%1.ini").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"))));
    }
    QFile::remove(p);
    QSettings dst(p, QSettings::IniFormat);
    dst.setValue(QStringLiteral("_backup/gcsVersion"), QStringLiteral(ML_GCS_VERSION));
    dst.setValue(QStringLiteral("_backup/created"), QDateTime::currentDateTime().toString(Qt::ISODate));
    for (const QString &k : src.allKeys()) {
        dst.setValue(k, src.value(k));
    }
    dst.sync();
    return dst.status() == QSettings::NoError ? p : QString();
}

QString MLSystem::restoreSettings(const QString &path)
{
    QString p = path;
    if (p.startsWith(QLatin1String("file:"))) p = QUrl(p).toLocalFile();
    if (!QFileInfo::exists(p)) return tr("파일이 없습니다");
    QSettings src(p, QSettings::IniFormat);
    if (src.status() != QSettings::NoError || !src.contains(QStringLiteral("_backup/gcsVersion"))) {
        return tr("MobilityLab GCS 설정 백업 파일이 아닙니다");
    }
    // vehicles armed → refuse: a restart is needed afterwards
    QmlObjectListModel *vs = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vs->count(); i++) {
        if (Vehicle *v = qobject_cast<Vehicle *>(vs->get(i)); v && v->armed()) return tr("시동이 걸린 기체가 있어 복원하지 않았습니다");
    }
    QSettings dst;
    for (const QString &k : src.allKeys()) {
        if (!k.startsWith(QLatin1String("_backup/"))) dst.setValue(k, src.value(k));
    }
    dst.sync();
    return QString();
}

QString MLSystem::writeDiagnostics(const QString &path)
{
    QString p = path;
    if (p.startsWith(QLatin1String("file:"))) p = QUrl(p).toLocalFile();
    if (p.isEmpty()) {
        QDir().mkpath(dataDir());
        p = QDir(dataDir()).filePath(QStringLiteral("MobilityLabGCS-diagnostics-%1.txt").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"))));
    }
    QFile f(p);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return QString();
    QTextStream ts(&f);
    ts << "MobilityLab GCS diagnostic report\n";
    ts << "created: " << QDateTime::currentDateTime().toString(Qt::ISODate) << "\n";
    ts << "gcs: " << ML_GCS_VERSION << "  qt: " << qVersion() << "\n";
    ts << "os: " << QSysInfo::prettyProductName() << " (" << QSysInfo::currentCpuArchitecture() << ", kernel " << QSysInfo::kernelVersion() << ")\n";
    ts << "previous session ended abnormally: " << (_prevCrash ? "yes" : "no") << "\n";
    for (QScreen *s : QGuiApplication::screens()) {
        ts << "screen: " << s->name() << " " << s->geometry().width() << "x" << s->geometry().height() << " dpr " << s->devicePixelRatio() << " dpi " << s->logicalDotsPerInch() << "\n";
    }
    ts << "settings file: " << QSettings().fileName() << "\n";
    ts << "data folder: " << dataDir() << "\n";
    QmlObjectListModel *vs = MultiVehicleManager::instance()->vehicles();
    ts << "vehicles connected: " << vs->count() << "\n";
    for (int i = 0; i < vs->count(); i++) {
        if (Vehicle *v = qobject_cast<Vehicle *>(vs->get(i))) {
            ts << "  sysid " << v->id() << " " << v->vehicleTypeString() << " " << v->firmwareTypeString() << " "
               << v->firmwareMajorVersion() << "." << v->firmwareMinorVersion() << "." << v->firmwarePatchVersion() << " armed " << v->armed() << "\n";
        }
    }
    ts << "\n[settings — values of keys that may hold keys, tokens or locations are removed]\n";
    QSettings s;
    for (const QString &k : s.allKeys()) {
        ts << k << " = " << (secretKey(k) ? QStringLiteral("<removed>") : s.value(k).toString().left(120)) << "\n";
    }
    return p;
}

// ---- update ---------------------------------------------------------------------------------------
int MLSystem::compareVersions(const QString &a, const QString &b)
{
    const QStringList x = QString(a).remove(QLatin1Char('v')).section(QLatin1Char('-'), 0, 0).split(QLatin1Char('.'));
    const QStringList y = QString(b).remove(QLatin1Char('v')).section(QLatin1Char('-'), 0, 0).split(QLatin1Char('.'));
    for (int i = 0; i < 3; i++) {
        const int p = x.value(i).toInt(), q = y.value(i).toInt();
        if (p != q) return p < q ? -1 : 1;
    }
    return 0;
}

void MLSystem::_set(const QString &state, const QString &text)
{
    _state = state;
    _text = text;
    emit updateChanged();
}

void MLSystem::checkForUpdate()
{
    if (!_nam) _nam = new QNetworkAccessManager(this);
    _set(QStringLiteral("checking"), tr("새 버전 확인 중…"));
    QNetworkRequest rq(QUrl(QStringLiteral("https://api.github.com/repos/%1/releases?per_page=10").arg(QLatin1String(kRepo))));
    rq.setRawHeader("Accept", "application/vnd.github+json");
    rq.setRawHeader("User-Agent", "MobilityLabGCS");
    QNetworkReply *r = _nam->get(rq);
    connect(r, &QNetworkReply::finished, this, [this, r]() {
        r->deleteLater();
        if (r->error() != QNetworkReply::NoError) {
            _set(QStringLiteral("failed"), tr("확인 실패: %1").arg(r->errorString()));
            return;
        }
        const QJsonArray rel = QJsonDocument::fromJson(r->readAll()).array();
        QJsonObject best;
        QString bestV;
        for (const QJsonValue &x : rel) {
            const QJsonObject o = x.toObject();
            if (o.value(QStringLiteral("draft")).toBool()) continue;
            const QString tag = o.value(QStringLiteral("tag_name")).toString();
            if (bestV.isEmpty() || compareVersions(tag, bestV) > 0) { bestV = tag; best = o; }
        }
        if (bestV.isEmpty() || compareVersions(bestV, QStringLiteral(ML_GCS_VERSION)) <= 0) {
            _latest = bestV;
            _set(QStringLiteral("none"), tr("최신 버전입니다 (%1)").arg(QStringLiteral(ML_GCS_VERSION)));
            return;
        }
        _latest = bestV;
        _releaseUrl = best.value(QStringLiteral("html_url")).toString();
        _assetUrl.clear(); _sumsUrl.clear(); _assetName.clear();
        for (const QJsonValue &a : best.value(QStringLiteral("assets")).toArray()) {
            const QJsonObject ao = a.toObject();
            const QString n = ao.value(QStringLiteral("name")).toString();
            if (n.endsWith(QLatin1String("Windows-Setup.exe"))) { _assetUrl = ao.value(QStringLiteral("browser_download_url")).toString(); _assetName = n; }
            if (n == QLatin1String("SHA256SUMS.txt")) _sumsUrl = ao.value(QStringLiteral("browser_download_url")).toString();
        }
        const bool pre = best.value(QStringLiteral("prerelease")).toBool();
        _set(QStringLiteral("available"), tr("새 버전 %1%2 — 받기 전에 변경 사항을 확인하세요").arg(bestV, pre ? tr(" (시험판 · 실기체 검증 전)") : QString()));
    });
}

void MLSystem::downloadUpdate()
{
#ifndef Q_OS_WIN
    _set(QStringLiteral("failed"), tr("자동 설치는 Windows 설치형에서만 됩니다 — 릴리스 페이지에서 받으세요"));
    return;
#else
    if (_assetUrl.isEmpty() || _sumsUrl.isEmpty()) {
        _set(QStringLiteral("failed"), tr("설치 파일 또는 체크섬 파일이 릴리스에 없습니다"));
        return;
    }
    if (!_nam) _nam = new QNetworkAccessManager(this);
    _set(QStringLiteral("downloading"), tr("체크섬 받는 중…"));
    QNetworkRequest sr{QUrl(_sumsUrl)};
    sr.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *s = _nam->get(sr);
    connect(s, &QNetworkReply::finished, this, [this, s]() {
        s->deleteLater();
        QString expect;
        for (const QString &line : QString::fromUtf8(s->readAll()).split(QLatin1Char('\n'))) {
            if (line.trimmed().endsWith(_assetName)) expect = line.section(QLatin1Char(' '), 0, 0).trimmed().toLower();
        }
        if (expect.size() != 64) { _set(QStringLiteral("failed"), tr("체크섬을 찾지 못했습니다 — 설치하지 않습니다")); return; }
        _file = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath(_assetName);
        QNetworkRequest rq{QUrl(_assetUrl)};
        rq.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply *r = _nam->get(rq);
        connect(r, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
            _progress = total > 0 ? double(got) / double(total) : 0;
            _set(QStringLiteral("downloading"), tr("받는 중 %1%").arg(int(_progress * 100)));
        });
        connect(r, &QNetworkReply::finished, this, [this, r, expect]() {
            r->deleteLater();
            if (r->error() != QNetworkReply::NoError) { _set(QStringLiteral("failed"), tr("받기 실패: %1").arg(r->errorString())); return; }
            const QByteArray data = r->readAll();
            const QString got = QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
            if (got != expect) { _set(QStringLiteral("failed"), tr("체크섬 불일치 — 받은 파일을 지웠고 설치하지 않습니다")); return; }
            QFile f(_file);
            if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size()) { _set(QStringLiteral("failed"), tr("임시 폴더에 저장하지 못했습니다")); return; }
            f.close();
            _set(QStringLiteral("verified"), tr("받기 완료 · SHA256 일치 — 기체가 모두 꺼진 상태에서 설치하세요"));
        });
    });
#endif
}

QString MLSystem::installUpdate()
{
    if (_state != QLatin1String("verified") || !QFileInfo::exists(_file)) return tr("검증된 설치 파일이 없습니다");
    QmlObjectListModel *vs = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vs->count(); i++) {
        if (Vehicle *v = qobject_cast<Vehicle *>(vs->get(i)); v && (v->armed() || v->flying())) return tr("시동이 걸렸거나 비행 중인 기체가 있습니다 — 설치하지 않습니다");
    }
    if (!QProcess::startDetached(_file, {})) return tr("설치 프로그램을 실행하지 못했습니다");
    QTimer::singleShot(500, qApp, &QCoreApplication::quit);
    return QString();
}
