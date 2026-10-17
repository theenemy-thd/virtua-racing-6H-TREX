"""Make IPS and BPS patches from an original and a modified ROM (same size)."""
import sys, zlib
def ips(a, b):
    out = bytearray(b'PATCH'); i = 0; n = len(b)
    while i < n:
        if a[i] == b[i]: i += 1; continue
        j = i
        # extend run while differing, bridging small equal gaps
        while j < n and j - i < 0xFFFF:
            if a[j] != b[j]: j += 1; continue
            k = j
            while k < n and a[k] == b[k] and k - j < 6: k += 1
            if k < n and k - j < 6 and a[k] != b[k] and k - i < 0xFFFF: j = k
            else: break
        if i == 0x454F46: i -= 1  # avoid 'EOF' offset
        out += i.to_bytes(3, 'big') + (j - i).to_bytes(2, 'big') + b[i:j]; i = j
    return bytes(out + b'EOF')
def num(v):
    o = bytearray()
    while True:
        x = v & 0x7F; v >>= 7
        if v == 0: o.append(0x80 | x); return o
        o.append(x); v -= 1
def bps(a, b):
    out = bytearray(b'BPS1') + num(len(a)) + num(len(b)) + num(0); i = 0; n = len(b)
    while i < n:
        j = i; same = a[i] == b[i] if i < len(a) else False
        while j < n and ((j < len(a) and a[j] == b[j]) == same): j += 1
        out += num(((j - i - 1) << 2) | (0 if same else 1))
        if not same: out += b[i:j]
        i = j
    for c in (zlib.crc32(a), zlib.crc32(b)): out += c.to_bytes(4, 'little')
    return bytes(out + zlib.crc32(out).to_bytes(4, 'little'))
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
open(sys.argv[3] + '.ips', 'wb').write(ips(a, b)); open(sys.argv[3] + '.bps', 'wb').write(bps(a, b))
