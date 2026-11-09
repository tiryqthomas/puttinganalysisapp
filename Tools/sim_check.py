"""Line-for-line Python mirror of PuttCore's simulator, detector and analyzer.

Swift can't run in every environment we work in, so this script checks the
detection algorithm against simulated strokes. If you change thresholds in
StrokeDetector.swift or StrokeAnalyzer.swift, change them here too.

    python3 Tools/sim_check.py
"""
import math
import random
NOISE = 0.02

# ---- Simulator (StrokeSimulator.swift) ----------------------------------

AXIS = [0.25, 0.92, 0.30]
n_ = math.sqrt(sum(a * a for a in AXIS))
AXIS = [a / n_ for a in AXIS]
SIDE = [AXIS[1], -AXIS[0], 0.0]
n_ = math.sqrt(sum(a * a for a in SIDE))
SIDE = [a / n_ for a in SIDE]


def simulate(A, tb, td, ratio, t0, rng, noise=None, rate=100, before=0.8, after=0.8):
    noise = NOISE if noise is None else noise
    F = A * ratio
    tf = ratio * td
    total = before + tb + td + tf + after
    out = []
    for k in range(int(total * rate)):
        t = k / rate
        u = t - before
        w = 0.0
        if 0 <= u < tb:
            w = A * math.pi / (2 * tb) * math.sin(math.pi * u / tb)
        elif tb <= u < tb + td:
            w = -A * math.pi / (2 * td) * math.sin(math.pi / 2 * (u - tb) / td)
        elif tb + td <= u < tb + td + tf:
            w = -F * math.pi / (2 * tf) * math.cos(math.pi / 2 * (u - tb - td) / tf)
        wob = 0.08 * w * math.sin(7 * t)
        a = w + rng.gauss(0, noise)
        b = wob + rng.gauss(0, noise)
        c = rng.gauss(0, noise * 0.5)
        r = [AXIS[i] * a + SIDE[i] * b for i in range(3)]
        r[2] += c
        out.append((t0 + t, r))
    return out


# ---- Analyzer (StrokeAnalyzer.swift) -------------------------------------

def principal_axis(rates):
    m = [[0.0] * 3 for _ in range(3)]
    for r in rates:
        for i in range(3):
            for j in range(3):
                m[i][j] += r[i] * r[j]
    k = max(range(3), key=lambda i: m[i][i])
    v = list(m[k])
    for _ in range(50):
        nx = [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]
        n = math.sqrt(sum(x * x for x in nx))
        if n < 1e-12:
            return None
        v = [x / n for x in nx]
    return v


def moving_average(x, width=5):
    if width <= 1 or len(x) <= width:
        return x
    half = width // 2
    out = []
    for i in range(len(x)):
        lo, hi = max(0, i - half), min(len(x) - 1, i + half)
        out.append(sum(x[lo:hi + 1]) / (hi - lo + 1))
    return out


def crossing_time(y, ts, i, level):
    if i < 0 or i + 1 >= len(y):
        return ts[max(0, min(i, len(ts) - 1))]
    a, b = y[i] - level, y[i + 1] - level
    if a == b:
        return ts[i]
    f = min(max(a / (a - b), 0), 1)
    return ts[i] + f * (ts[i + 1] - ts[i])


def analyze(samples, min_back=0.025, min_through=0.01):
    if len(samples) < 20:
        return "tooFewSamples"
    ts = [s[0] for s in samples]
    axis = principal_axis([s[1] for s in samples])
    if axis is None:
        return "noRotation"
    omega = moving_average([sum(s[1][i] * axis[i] for i in range(3)) for s in samples])
    theta = [0.0]
    for i in range(1, len(omega)):
        theta.append(theta[-1] + 0.5 * (omega[i] + omega[i - 1]) * (ts[i] - ts[i - 1]))
    peak = max(abs(x) for x in theta)
    first = next(x for x in theta if abs(x) > 0.25 * peak)
    if first < 0:
        omega = [-x for x in omega]
        theta = [-x for x in theta]
    i_top = max(range(len(theta)), key=lambda i: theta[i])
    top = theta[i_top]
    if top < min_back:
        return "backswingTooShort"
    i_pk = max(range(i_top + 1), key=lambda i: omega[i])
    onset = max(0.05 * omega[i_pk], 0.02)
    i_start = 0
    for i in range(i_pk, -1, -1):
        if omega[i] <= onset:
            i_start = i
            break
    t_start = crossing_time(omega, ts, i_start, onset)
    i_imp = next((i for i in range(i_top + 1, len(theta)) if theta[i] <= 0), None)
    if i_imp is None:
        return "noImpact"
    t_imp = crossing_time(theta, ts, i_imp - 1, 0)
    j = max(1, min(i_imp, len(omega) - 1))
    f = min(max((t_imp - ts[j - 1]) / (ts[j] - ts[j - 1]), 0), 1)
    imp_speed = abs(omega[j - 1] + f * (omega[j] - omega[j - 1]))
    i_fin = min(range(i_imp, len(theta)), key=lambda i: theta[i])
    through = -theta[i_fin]
    if through < min_through:
        return "noImpact"
    bt = ts[i_top] - t_start
    dt = t_imp - ts[i_top]
    if not (0.2 <= bt <= 2.0 and 0.1 <= dt <= 1.2):
        return "timingOutOfRange"
    return dict(back=top, through=through, bt=bt, dt=dt, tempo=bt / dt, imp=imp_speed)


# ---- Detector (StrokeDetector.swift) -------------------------------------

class Detector:
    still, move, smooth = 0.07, 0.09, 0.2
    address_hold, finish_hold, max_dur, preroll, cooldown = 0.35, 0.3, 4.0, 0.3, 0.8

    def __init__(self):
        self.phase = "settling"
        self.hist, self.cap = [], []
        self.still_since = None
        self.cool_until = -1e9
        self.sm = [0.0, 0.0, 0.0]
        self.cap_start = 0

    def add(self, s):
        t, r = s
        self.sm = [self.sm[i] * (1 - self.smooth) + r[i] * self.smooth for i in range(3)]
        speed = math.sqrt(sum(x * x for x in self.sm))
        if speed < self.still:
            if self.still_since is None:
                self.still_since = t
        else:
            self.still_since = None
        still_for = t - self.still_since if self.still_since is not None else 0
        if self.phase in ("settling", "ready"):
            self.hist.append(s)
            self.hist = [h for h in self.hist if t - h[0] <= self.preroll]
            if self.phase == "settling" and still_for >= self.address_hold and t >= self.cool_until:
                self.phase = "ready"
            if self.phase == "ready" and speed > self.move:
                self.phase = "capturing"
                self.cap = list(self.hist)
                self.cap_start = t
                self.hist = []
            return None
        self.cap.append(s)
        if still_for >= self.finish_hold:
            w = self.cap
            self.cap = []
            self.phase = "settling"
            self.cool_until = t + self.cooldown
            return analyze(w)
        if t - self.cap_start > self.max_dur:
            self.cap = []
            self.phase = "settling"
            return "timingOutOfRange"
        return None


def main():
    rng = random.Random(7)
    lever = 1.1
    cases = []
    t = 0.0
    stream = []
    for _ in range(40):
        length = rng.uniform(0.04, 0.32)  # putter-head backswing, m
        td = 0.30 * (1 + 0.04 * rng.gauss(0, 1))
        tempo = 2.0 * (1 + 0.06 * rng.gauss(0, 1))
        ratio = 1.2 * (1 + 0.08 * rng.gauss(0, 1))
        A = length / lever
        s = simulate(A, td * tempo, td, ratio, t, rng)
        stream += s
        t = s[-1][0] + 0.01
        cases.append(dict(back=A, through=A * ratio, bt=td * tempo, dt=td, tempo=tempo,
                          imp=A * math.pi / (2 * td), len_cm=length * 100))
    det = Detector()
    found = []
    rejected = []
    for s in stream:
        e = det.add(s)
        if isinstance(e, dict):
            found.append(e)
        elif e is not None:
            rejected.append(e)
    print(f"strokes simulated: {len(cases)}  detected: {len(found)}  rejected windows: {rejected}")
    if len(found) != len(cases):
        print("MISMATCH in stroke count")
    worst = {k: 0.0 for k in ("back", "through", "bt", "dt", "tempo", "imp")}
    for c, f in zip(cases, found):
        for k in worst:
            worst[k] = max(worst[k], abs(f[k] - c[k]) / c[k])
    print("worst relative error per metric:")
    for k, v in worst.items():
        print(f"  {k:8s} {v * 100:5.1f}%")
    print("shortest backswing simulated: %.1f cm" % min(c["len_cm"] for c in cases))


if __name__ == "__main__":
    main()
