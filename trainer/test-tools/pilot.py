import math, pickle
from lr import BTN
def s16(v): return v - 0x10000 if v & 0x8000 else v
def car(e, n=0):
    b = 0xFF9000 + n * 0x100
    return s16(e.rd16(b + 0x2E)), s16(e.rd16(b + 0x32)), s16(e.rd16(b + 0x3A)), e.rd16(b + 0x22)
def record_path(e, frames, n=1, hold_time=True):
    pts = []
    for i in range(frames):
        if hold_time: e.wr16(0xFFD054, 75)
        e.run(1, 0)
        x, z, h, s = car(e, n)
        if not pts or (x - pts[-1][0]) ** 2 + (z - pts[-1][1]) ** 2 > 16: pts.append((x, z))
    return pts
class Pilot:
    def __init__(self, path, look=12):
        self.p = path; self.i = 0; self.look = look
    def step(self, e, extra=0, hold_time=False):
        x, z, h, s = car(e, 0)
        # nearest point, searching forward from the last one
        best, bi = 1e18, self.i
        n = len(self.p)
        for k in range(-5, 60):
            j = (self.i + k) % n
            d = (self.p[j][0] - x) ** 2 + (self.p[j][1] - z) ** 2
            if d < best: best, bi = d, j
        self.i = bi
        tx, tz = self.p[(bi + self.look) % n]
        want = math.atan2(tx - x, tz - z)          # angle where dx = sin, dz = cos
        have = -h / 32768 * math.pi
        err = (want - have + math.pi) % (2 * math.pi) - math.pi
        b = 1 << BTN['B']
        if err > 0.04: b |= 1 << BTN['RIGHT']
        elif err < -0.04: b |= 1 << BTN['LEFT']
        if hold_time: e.wr16(0xFFD054, 75)
        e.run(1, b | extra)
        return err
