"""Carve LECommonLibrary.dll out of the official LEInstaller.exe without
executing or loading it: scan for embedded PE images, compute each image's
size from its section table, and accept only the one whose SHA-256 matches."""
import hashlib, struct, sys

EXPECTED = "6EDBB48B891E3EE830E7B487F352D90044474A757905FF49D3B2ABFDB980C211"

def pe_size(buf, off):
    try:
        pe = off + struct.unpack_from("<I", buf, off + 0x3C)[0]
        if buf[pe:pe + 4] != b"PE\0\0":
            return None
        nsec = struct.unpack_from("<H", buf, pe + 6)[0]
        opt = struct.unpack_from("<H", buf, pe + 20)[0]
        sec = pe + 24 + opt
        end = 0
        for i in range(nsec):
            raw_size, raw_ptr = struct.unpack_from("<II", buf, sec + i * 40 + 16)
            end = max(end, raw_ptr + raw_size)
        return end
    except struct.error:
        return None

src, dst = sys.argv[1], sys.argv[2]
buf = open(src, "rb").read()
pos = 1
while (pos := buf.find(b"MZ", pos)) != -1:
    size = pe_size(buf, pos)
    if size:
        blob = buf[pos:pos + size]
        h = hashlib.sha256(blob).hexdigest().upper()
        print(f"embedded PE at {pos} size {size} sha256 {h}")
        if h == EXPECTED:
            open(dst, "wb").write(blob)
            print("written", dst)
            sys.exit(0)
    pos += 2
sys.exit("LECommonLibrary.dll with expected hash not found")
