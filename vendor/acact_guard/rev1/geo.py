"""geo.py — 위경도 ↔ 시연 프레임(F 전방, R 오른쪽) 변환"""
import json
import math
import os

import config as C

R_EARTH = 6378137.0


class Frame:
    def __init__(self, lat0, lon0, bearing_deg=0.0):
        self.lat0, self.lon0 = lat0, lon0
        self.b = math.radians(bearing_deg)
        self.cos0 = math.cos(math.radians(lat0))

    # NE ↔ FR
    def ne_to_fr(self, n, e):
        cb, sb = math.cos(self.b), math.sin(self.b)
        return n * cb + e * sb, -n * sb + e * cb

    def fr_to_ne(self, f, r):
        cb, sb = math.cos(self.b), math.sin(self.b)
        return f * cb - r * sb, f * sb + r * cb

    def ll_to_fr(self, lat, lon):
        n = math.radians(lat - self.lat0) * R_EARTH
        e = math.radians(lon - self.lon0) * R_EARTH * self.cos0
        return self.ne_to_fr(n, e)

    def fr_to_ll(self, f, r):
        n, e = self.fr_to_ne(f, r)
        lat = self.lat0 + math.degrees(n / R_EARTH)
        lon = self.lon0 + math.degrees(e / (R_EARTH * self.cos0))
        return lat, lon


def load_site(path=None):
    path = path or C.SITE_FILE
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)
