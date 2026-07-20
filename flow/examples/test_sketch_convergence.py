# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# End-to-end convergence proof for the sketch relay: three aioquic clients
# against a running picoquic_fanout_server.
#
#   A: "SKB <room>", draws a closed square (two CSP1 chunks, seq 0 and 1).
#   B: "SKB <room>", draws a line crossing the square.
#   C: joins LATE with "SKB <room>" only - receives the server's history
#      replay.
#
# Each client's knowledge = its own packets + every frame it received. Each
# log is written as [len u32 LE][CSP1] and replayed through the Lean core
# (lake exe sketch_graph_dump); all three canonical graph JSONs must be
# byte-identical, and the graph must contain at least one cycle (the
# square).

import argparse
import os
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import time

from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.connection import QuicConnection
from aioquic.quic.events import StreamDataReceived, HandshakeCompleted

CSP1_MAGIC = 0x31505343


def encode_csp1(peer_id, stroke_id, seq, closed, samples):
    """samples: list of (x, y, z, pressure) floats."""
    out = struct.pack(
        "<IIIHHBB", CSP1_MAGIC, peer_id, stroke_id, seq, len(samples),
        1 if closed else 0, 0)
    for x, y, z, p in samples:
        out += struct.pack("<ffff", x, y, z, p)
    return out


def frame(packet):
    return struct.pack("<I", len(packet)) + packet


class Client:
    def __init__(self, addr):
        self.addr = addr
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.settimeout(0.05)
        config = QuicConfiguration(is_client=True, alpn_protocols=["fanout-demo"])
        config.verify_mode = ssl.CERT_NONE
        self.conn = QuicConnection(configuration=config)
        self.conn.connect(self.addr, now=time.time())
        self.received = bytearray()
        self.handshake_done = False
        self._flush()

    def _flush(self):
        for data, _addr in self.conn.datagrams_to_send(now=time.time()):
            self.sock.sendto(data, self.addr)

    def pump(self, deadline):
        while time.time() < deadline:
            timer = self.conn.get_timer()
            if timer is not None and timer <= time.time():
                self.conn.handle_timer(now=time.time())
                self._flush()
            try:
                data, _from = self.sock.recvfrom(65536)
            except socket.timeout:
                continue
            except ConnectionResetError:
                continue
            self.conn.receive_datagram(data, self.addr, now=time.time())
            self._flush()
            while True:
                event = self.conn.next_event()
                if event is None:
                    break
                if isinstance(event, HandshakeCompleted):
                    self.handshake_done = True
                elif isinstance(event, StreamDataReceived):
                    self.received += event.data

    def wait_for_handshake(self, timeout=5.0):
        deadline = time.time() + timeout
        while not self.handshake_done and time.time() < deadline:
            self.pump(min(time.time() + 0.05, deadline))
        if not self.handshake_done:
            raise RuntimeError("handshake did not complete")

    def send(self, stream_id, data):
        self.conn.send_stream_data(stream_id, data)
        self._flush()

    def received_frames(self):
        """Parse [len][CSP1] frames out of the received stream bytes."""
        frames = []
        buf = bytes(self.received)
        off = 0
        while off + 4 <= len(buf):
            (length,) = struct.unpack_from("<I", buf, off)
            if off + 4 + length > len(buf):
                break
            frames.append(buf[off + 4:off + 4 + length])
            off += 4 + length
        return frames


def dump_graph(lake, sketch_core_dir, packets, tag):
    path = os.path.join(tempfile.gettempdir(), f"sketch_conv_{tag}_{os.getpid()}.bin")
    with open(path, "wb") as f:
        for p in packets:
            f.write(frame(p))
    out = subprocess.run(
        [lake, "exe", "sketch_graph_dump", path],
        cwd=sketch_core_dir, capture_output=True, text=True)
    os.unlink(path)
    if out.returncode != 0:
        raise RuntimeError(f"sketch_graph_dump({tag}) failed: {out.stderr}")
    return out.stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4433)
    parser.add_argument("--room", default="sketchroom")
    args = parser.parse_args()
    addr = ("127.0.0.1", args.port)

    lake = os.environ.get("LAKE") or shutil.which("lake")
    if not lake:
        print("FAIL: lake not found (set LAKE or add elan to PATH)", file=sys.stderr)
        sys.exit(1)
    sketch_core_dir = os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sketch-core"))

    header = f"SKB {args.room}\n".encode()

    # A: closed square in two chunks.
    a_pkts = [
        encode_csp1(1, 1, 0, False, [(0, 0, 0, 1.0), (10, 0, 0, 1.0)]),
        encode_csp1(1, 1, 1, True, [(10, 10, 0, 1.0), (0, 10, 0, 1.0)]),
    ]
    # B: a line crossing the square.
    b_pkts = [
        encode_csp1(2, 1, 0, False, [(-5, 5, 0, 1.0), (15, 5, 0, 1.0)]),
    ]

    a = Client(addr)
    a.wait_for_handshake()
    a.send(0, header)
    a.pump(time.time() + 0.3)

    b = Client(addr)
    b.wait_for_handshake()
    b.send(0, header)
    b.pump(time.time() + 0.3)

    for p in a_pkts:
        a.send(0, frame(p))
    a.pump(time.time() + 0.5)
    for p in b_pkts:
        b.send(0, frame(p))
    b.pump(time.time() + 0.5)

    # Let the relay settle both ways.
    a.pump(time.time() + 1.0)
    b.pump(time.time() + 1.0)

    # C joins late; must receive the full history replay.
    c = Client(addr)
    c.wait_for_handshake()
    c.send(0, header)
    c.pump(time.time() + 2.0)

    a_log = a_pkts + a.received_frames()
    b_log = b_pkts + b.received_frames()
    c_log = c.received_frames()

    if len(c_log) != 3:
        print(f"FAIL: late joiner received {len(c_log)} packets, expected 3",
              file=sys.stderr)
        sys.exit(1)

    ja = dump_graph(lake, sketch_core_dir, a_log, "a")
    jb = dump_graph(lake, sketch_core_dir, b_log, "b")
    jc = dump_graph(lake, sketch_core_dir, c_log, "c")

    if not (ja == jb == jc):
        print("FAIL: graphs diverged", file=sys.stderr)
        print(f"A: {ja}", file=sys.stderr)
        print(f"B: {jb}", file=sys.stderr)
        print(f"C: {jc}", file=sys.stderr)
        sys.exit(1)

    if '"cycles":0' in ja:
        print(f"FAIL: expected at least one cycle, got {ja}", file=sys.stderr)
        sys.exit(1)

    print("OK: three clients (one late joiner) converged to identical sketch graphs")
    print(f"graph: {ja}")


if __name__ == "__main__":
    main()
