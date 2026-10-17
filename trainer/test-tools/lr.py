# Minimal headless libretro frontend (Genesis Plus GX / PicoDrive) via ctypes.
import ctypes as C, os, shutil, tempfile, struct, zlib
BTN = dict(B=0, A=1, SELECT=2, START=3, UP=4, DOWN=5, LEFT=6, RIGHT=7, C=8, Y=9, X=10, Z=11)
# MD pad -> libretro ids (GPGX): MD A=RETRO_Y(1), MD B=RETRO_B(0), MD C=RETRO_A(8), MD Y=RETRO_X(9), MD X=L(10), MD Z=R(11)
ENVCB = C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)
VIDCB = C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)
AUDCB = C.CFUNCTYPE(None, C.c_int16, C.c_int16)
AUDBCB = C.CFUNCTYPE(C.c_size_t, C.c_void_p, C.c_size_t)
POLLCB = C.CFUNCTYPE(None)
INCB = C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)
class GameInfo(C.Structure):
    _fields_ = [('path', C.c_char_p), ('data', C.c_void_p), ('size', C.c_size_t), ('meta', C.c_char_p)]
class Var(C.Structure):
    _fields_ = [('key', C.c_char_p), ('value', C.c_char_p)]
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CORE = os.path.expanduser('~/emu/gpgxdbg/genesis_plus_gx_libretro.so')

class Emu:
    def __init__(self, rom, core=None, sram=None, opts=None):
        core = core or os.environ.get('CORE', DEFAULT_CORE)
        self.tmp = tempfile.mkdtemp()
        so = os.path.join(self.tmp, 'core.so'); shutil.copy(core, so)
        self.L = L = C.CDLL(so)
        self.pico = 'pico' in os.path.basename(core)
        self.buttons = 0
        self.frame = None; self.w = self.h = self.pitch = 0
        self.opts = {b'genesis_plus_gx_bram': b'per game', b'picodrive_input1': b'6 button pad',
                     b'genesis_plus_gx_input_hw1': b'6 button gamepad'} if opts is None else opts
        self.sysdir = C.c_char_p(self.tmp.encode())
        self._keep = []
        def env(cmd, data):
            if cmd == 10:  # SET_PIXEL_FORMAT
                self.fmt = C.cast(data, C.POINTER(C.c_int))[0]; return True
            if cmd in (9, 31):  # SYSTEM_DIRECTORY / SAVE_DIRECTORY
                C.cast(data, C.POINTER(C.c_char_p))[0] = self.sysdir; return True
            if cmd == 15:
                v = C.cast(data, C.POINTER(Var))[0]
                val = self.opts.get(v.key)
                if val is not None:
                    C.cast(data, C.POINTER(Var))[0].value = val; return True
                return False
            if cmd == 17: C.cast(data, C.POINTER(C.c_bool))[0] = False; return True
            if cmd == 3: C.cast(data, C.POINTER(C.c_bool))[0] = True; return True  # CAN_DUPE
            if cmd == 52: C.cast(data, C.POINTER(C.c_uint))[0] = 0; return True   # core options version
            if cmd == (47 | 0x10000): C.cast(data, C.POINTER(C.c_int))[0] = 3; return True  # AV enable
            return False
        def vid(data, w, h, pitch):
            if data:
                self.w, self.h, self.pitch = w, h, pitch
                self.frame = C.string_at(data, pitch * h)
        def aud(l, r): pass
        def audb(d, n): return n
        def poll(): pass
        def inp(port, dev, idx, id):
            if port != 0: return 0
            if id == 256: return self.buttons
            return (self.buttons >> id) & 1
        self.cbs = [ENVCB(env), VIDCB(vid), AUDCB(aud), AUDBCB(audb), POLLCB(poll), INCB(inp)]
        L.retro_set_environment(self.cbs[0]); L.retro_set_video_refresh(self.cbs[1])
        L.retro_set_audio_sample(self.cbs[2]); L.retro_set_audio_sample_batch(self.cbs[3])
        L.retro_set_input_poll(self.cbs[4]); L.retro_set_input_state(self.cbs[5])
        L.retro_init()
        romdata = open(rom, 'rb').read()
        rp = os.path.join(self.tmp, 'game.bin'); open(rp, 'wb').write(romdata)
        self.rombuf = C.create_string_buffer(romdata)
        gi = GameInfo(rp.encode(), C.cast(self.rombuf, C.c_void_p), len(romdata), None)
        L.retro_get_memory_data.restype = C.c_void_p
        L.retro_get_memory_size.restype = C.c_size_t
        L.retro_serialize_size.restype = C.c_size_t
        assert L.retro_load_game(C.byref(gi)), 'load failed'
        L.retro_set_controller_port_device(0, 1)
        if sram is not None:
            p = L.retro_get_memory_data(0); n = L.retro_get_memory_size(0)
            C.memmove(p, sram, min(n, len(sram)))
        self.ramp = L.retro_get_memory_data(2)
        self.swap = not self.pico or True
        self.nframes = 0
    # --- memory (68k address $FFxxxx); GPGX/PicoDrive store words host-endian
    def rd8(self, a):
        return C.cast(self.ramp, C.POINTER(C.c_uint8))[(a & 0xFFFF) ^ 1]
    def wr8(self, a, v):
        C.cast(self.ramp, C.POINTER(C.c_uint8))[(a & 0xFFFF) ^ 1] = v & 0xFF
    def rd16(self, a): return (self.rd8(a) << 8) | self.rd8(a + 1)
    def rd32(self, a): return (self.rd16(a) << 16) | self.rd16(a + 2)
    def wr16(self, a, v): self.wr8(a, v >> 8); self.wr8(a + 1, v)
    def ram(self):
        raw = C.string_at(self.ramp, 0x10000)
        b = bytearray(0x10000); b[0::2] = raw[1::2]; b[1::2] = raw[0::2]
        return bytes(b)
    def sram(self):
        return C.string_at(self.L.retro_get_memory_data(0), self.L.retro_get_memory_size(0))
    def run(self, n=1, buttons=None):
        if buttons is not None: self.buttons = buttons
        for _ in range(n):
            self.L.retro_run(); self.nframes += 1
    def press(self, names, hold=4, after=10):
        m = 0
        for s in names.split('+'): m |= 1 << BTN[s]
        self.run(hold, m); self.run(after, 0)
    def save(self):
        n = self.L.retro_serialize_size(); b = C.create_string_buffer(n)
        assert self.L.retro_serialize(b, n); return b.raw
    def load(self, s):
        b = C.create_string_buffer(s, len(s)); assert self.L.retro_unserialize(b, len(s))
    def png(self, path):
        w, h, p = self.w, self.h, self.pitch
        rows = []
        for y in range(h):
            row = bytearray([0])
            line = self.frame[y * p:y * p + w * 2]
            for x in range(w):
                v = line[2 * x] | (line[2 * x + 1] << 8)
                if getattr(self, 'fmt', 2) == 2:
                    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
                    row += bytes([r * 255 // 31, g * 255 // 63, b * 255 // 31])
                else:
                    r, g, b = (v >> 10) & 31, (v >> 5) & 31, v & 31
                    row += bytes([r * 255 // 31, g * 255 // 31, b * 255 // 31])
            rows.append(bytes(row))
        raw = zlib.compress(b''.join(rows))
        def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
        open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', raw) + chunk(b'IEND', b''))
    # --- debug core only
    def watch(self, lo, hi=None):
        self.L.retro_dbg_enable(1); self.L.retro_dbg_watch(lo, hi if hi is not None else lo); self.L.retro_dbg_clear()
    def rwatch(self, lo, hi=None):
        self.L.retro_dbg_enable(1); self.L.retro_dbg_rwatch(lo, hi if hi is not None else lo); self.L.retro_dbg_clear()
    def log(self):
        self.L.retro_dbg_log.restype = C.POINTER(C.c_uint)
        n = self.L.retro_dbg_nlog(); p = self.L.retro_dbg_log()
        return [tuple(p[i * 5 + j] for j in range(5)) for i in range(n)]
    def unwatch(self):
        self.L.retro_dbg_enable(0); self.L.retro_dbg_watch(1, 0); self.L.retro_dbg_rwatch(1, 0)

def sheet(paths, out, cols=4):
    from PIL import Image
    ims = [Image.open(p) for p in paths]
    w, h = 320, 224
    rows = (len(ims) + cols - 1) // cols
    o = Image.new('RGB', (w * cols, h * rows))
    for i, im in enumerate(ims): o.paste(im, ((i % cols) * w, (i // cols) * h))
    o.save(out)
