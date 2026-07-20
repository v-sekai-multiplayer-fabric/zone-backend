# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# Real end-to-end proof for picoquic_fanout_server: two aioquic low-level
# QUIC connections against the running server. One subscribes to a topic;
# the other publishes a 100-byte payload to it; the subscriber must receive
# those exact bytes on its stream. Run the server first, then this script.

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
                # Windows surfaces an ICMP port-unreachable for a prior
                # datagram as a WSAECONNRESET on the next recv; harmless
                # for a client that keeps retransmitting.
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
    parser.add_argument("--topic", default="room1")
    args = parser.parse_args()
    addr = ("127.0.0.1", args.port)

    sub = Client(addr)
    sub.wait_for_handshake()
    sub.send_line(0, f"SUB {args.topic}\n")
    sub.pump(time.time() + 0.5)

    pub = Client(addr)
    pub.wait_for_handshake()
    payload = bytes((i % 256 for i in range(ENTITY_PACKET_SIZE)))
    pub.send_line(0, f"PUB {args.topic}\n")
    pub.send_bytes(0, payload)
    pub.pump(time.time() + 0.5)

    sub.pump(time.time() + 2.0)

    if bytes(sub.received) != payload:
        print(
            f"FAIL: subscriber received {len(sub.received)} bytes, "
            f"expected {ENTITY_PACKET_SIZE} matching bytes",
            file=sys.stderr,
        )
        print(f"got: {bytes(sub.received)!r}", file=sys.stderr)
        sys.exit(1)

    print("OK: subscriber received the published payload byte-for-byte")


if __name__ == "__main__":
    main()
