# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# Real end-to-end proof for picoquic_fanout_server's ZPB verb (ADR 0008/0009
# zone-authority/interest dispatch): two aioquic connections, each sends
# "ZPB <x> <y> <z> <vx> <vy> <vz>\n" + a distinct 100-byte payload landing
# in the one
# default zone the server allocates at startup (fanout_core_ffi.cpp), and
# each must receive the OTHER's payload - not its own - via zone-based
# fanout, not the flat per-topic broadcast test_picoquic_fanout.py already
# proves. Mirrors that script's own Client harness exactly; run the server
# first, then this script.

import argparse
import socket
import ssl
import sys
import time

from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.connection import QuicConnection
from aioquic.quic.events import StreamDataReceived, HandshakeCompleted

ENTITY_PACKET_SIZE = 100


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

    def send_line(self, stream_id, text):
        self.conn.send_stream_data(stream_id, text.encode("utf-8"))
        self._flush()

    def send_bytes(self, stream_id, data):
        self.conn.send_stream_data(stream_id, data)
        self._flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4433)
    args = parser.parse_args()
    addr = ("127.0.0.1", args.port)

    # A joins the (one, default) zone first. Nobody else is in it yet, so
    # this first publish reaches no one - that's expected, not a failure.
    a = Client(addr)
    a.wait_for_handshake()
    payload_a1 = bytes((i % 256 for i in range(ENTITY_PACKET_SIZE)))
    a.send_line(0, "ZPB 0 0 0 0 0 0\n")
    a.send_bytes(0, payload_a1)
    a.pump(time.time() + 0.3)

    # B joins next. A is already a zone member, so B's join-publish SHOULD
    # reach A.
    b = Client(addr)
    b.wait_for_handshake()
    payload_b = bytes(((i + 1) % 256 for i in range(ENTITY_PACKET_SIZE)))
    b.send_line(0, "ZPB 1 2 3 0 0 0\n")
    b.send_bytes(0, payload_b)
    b.pump(time.time() + 1.0)
    a.pump(time.time() + 1.0)

    # A publishes again, now that B is a zone member - this second publish
    # SHOULD reach B. A distinct payload from A's first (which nobody
    # could have received) keeps the assertion unambiguous.
    payload_a2 = bytes(((i + 2) % 256 for i in range(ENTITY_PACKET_SIZE)))
    a.send_line(0, "ZPB 4 5 6 0 0 0\n")
    a.send_bytes(0, payload_a2)
    a.pump(time.time() + 1.0)
    b.pump(time.time() + 1.0)

    ok = True
    if bytes(a.received) != payload_b:
        print(f"FAIL: a expected b's payload, got {len(a.received)} bytes: {bytes(a.received)!r}", file=sys.stderr)
        ok = False
    if bytes(b.received) != payload_a2:
        print(f"FAIL: b expected a's second payload, got {len(b.received)} bytes: {bytes(b.received)!r}", file=sys.stderr)
        ok = False
    if payload_a1 in b.received or payload_a1 in a.received:
        print("FAIL: a's first (pre-B-joining) payload was delivered to someone - should have reached no one",
              file=sys.stderr)
        ok = False
    if payload_b in b.received:
        print("FAIL: b received its own payload back (should never happen - publisher excluded)", file=sys.stderr)
        ok = False

    if not ok:
        sys.exit(1)
    print("OK: ZPB zone-based fanout delivered each entity's payload to the other, not to itself, "
          "and not before the other actually joined the zone")


if __name__ == "__main__":
    main()
