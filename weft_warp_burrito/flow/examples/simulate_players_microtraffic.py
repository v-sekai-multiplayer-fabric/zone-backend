# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# A microscopic traffic simulation: a handful of simulated players, each
# driven by a tiny RECTGTN-style plan/execute/replan loop, generating real
# QUIC wire traffic against a running picoquic_fanout_server. This is not a
# taskweft integration - taskweft (github.com/taskweft/taskweft) is a
# separate C++20/NIF planner that isn't vendored into this repo, and pulling
# it in for a tiny local test would be a bigger dependency than this test
# needs (Gall's Law: prove the small thing first). What this script borrows
# from taskweft's own documented discipline (docs/rectgtn.md) is the shape
# of the loop, not the library: each simulated player carries a small
# todo-list of goals, executes them one at a time against the real server,
# and re-decomposes its plan from fresh state - reconnect, then resume -
# instead of blindly retrying the step that failed.
#
# Scale is deliberately small (ADR 0008's 8,000/10,000-player figures are a
# sizing reference, not a target this script drives toward): a handful of
# players is enough to see real fanout traffic on the wire and measure its
# shape (packet counts, byte volume, per-player cadence) without needing a
# fleet of world servers to interpret the result.
#
# Run the server first (fanout_server_main), then this script.

import argparse
import socket
import ssl
import sys
import threading
import time
from dataclasses import dataclass, field

from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.connection import QuicConnection
from aioquic.quic.events import StreamDataReceived, HandshakeCompleted

ENTITY_PACKET_SIZE = 100


class Client:
    """Same minimal aioquic harness test_picoquic_fanout.py already proved
    works end-to-end against the real server; reused here rather than
    reinvented."""

    def __init__(self, addr):
        self.addr = addr
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.settimeout(0.02)
        config = QuicConfiguration(is_client=True, alpn_protocols=["fanout-demo"])
        config.verify_mode = ssl.CERT_NONE
        self.conn = QuicConnection(configuration=config)
        self.conn.connect(self.addr, now=time.time())
        self.received = bytearray()
        self.handshake_done = False
        self.bytes_sent = 0
        self.bytes_received = 0
        self.packets_sent = 0
        self.packets_received = 0
        self._flush()

    def _flush(self):
        for data, _addr in self.conn.datagrams_to_send(now=time.time()):
            self.sock.sendto(data, self.addr)
            self.bytes_sent += len(data)
            self.packets_sent += 1

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
            self.bytes_received += len(data)
            self.packets_received += 1
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
            self.pump(min(time.time() + 0.02, deadline))
        if not self.handshake_done:
            raise RuntimeError("handshake did not complete")

    def send_line(self, stream_id, text):
        self.conn.send_stream_data(stream_id, text.encode("utf-8"))
        self._flush()

    def send_bytes(self, stream_id, data):
        self.conn.send_stream_data(stream_id, data)
        self._flush()

    def close(self):
        self.sock.close()


@dataclass
class PlayerPlan:
    """A todo-list of goals, RECTGTN-style: executed in order, and
    re-decomposed (not just retried) from fresh state on failure."""

    player_id: int
    room: str
    tick_count: int
    todo: list = field(default_factory=list)

    def decompose(self):
        # Fresh state -> fresh todo-list: connect, subscribe, then one PUB
        # goal per tick. Called both at the start and on replan.
        self.todo = ["connect", "sub"] + ["pub"] * self.tick_count


def make_payload(player_id, tick):
    # 100-byte lean-entity-packet payload; content only needs to be
    # deterministic per (player, tick), not meaningful.
    seed = (player_id * 1000 + tick) % 256
    return bytes((seed + i) % 256 for i in range(ENTITY_PACKET_SIZE))


def run_player(addr, plan, tick_interval, max_replans=2):
    """Executes a PlayerPlan's todo-list against the real server, replanning
    (reconnect + redo the whole todo-list from the failed goal onward) up to
    max_replans times on failure, matching RECTGTN's plan/execute/replan
    discipline rather than blind per-step retry."""

    plan.decompose()
    replans = 0
    client = None
    tick = 0
    pubs_sent = 0

    while plan.todo:
        goal = plan.todo[0]
        try:
            if goal == "connect":
                client = Client(addr)
                client.wait_for_handshake()
                plan.todo.pop(0)
            elif goal == "sub":
                client.send_line(0, f"SUB {plan.room}\n")
                client.pump(time.time() + 0.1)
                plan.todo.pop(0)
            elif goal == "pub":
                payload = make_payload(plan.player_id, tick)
                client.send_line(4 + 4 * tick, f"PUB {plan.room}\n")
                client.send_bytes(4 + 4 * tick, payload)
                client.pump(time.time() + tick_interval)
                tick += 1
                pubs_sent += 1
                plan.todo.pop(0)
        except (RuntimeError, OSError) as exc:
            replans += 1
            if replans > max_replans:
                raise
            if client is not None:
                client.close()
            # Re-decompose from current tick, not from scratch: a player
            # that already sent 3 of 10 pubs resumes at pub 4, it doesn't
            # replay the ones that already landed.
            remaining_pubs = plan.tick_count - tick
            plan.todo = ["connect", "sub"] + ["pub"] * remaining_pubs
            print(f"player {plan.player_id}: replan #{replans} after {exc}", file=sys.stderr)

    return client, pubs_sent


@dataclass
class RoundResult:
    player_count: int
    succeeded: int
    failed: int
    failure_messages: list
    clients: list
    total_pubs: int
    elapsed: float


def run_round(addr, room, player_count, ticks, tick_interval):
    """Runs player_count simulated players concurrently (real threads, real
    independent QUIC connections - not the sequential loop this script
    started with, which never gave players a chance to overlap in the
    room). Each player's failure is caught independently so one player's
    replan-exhaustion doesn't abort the others; the round's result reports
    how many players actually held up under the given concurrency."""

    results = [None] * player_count
    errors = [None] * player_count

    def worker(player_id):
        plan = PlayerPlan(player_id=player_id, room=room, tick_count=ticks)
        try:
            client, pubs_sent = run_player(addr, plan, tick_interval)
            results[player_id] = (client, pubs_sent)
        except (RuntimeError, OSError) as exc:
            errors[player_id] = str(exc)

    started = time.time()
    threads = [threading.Thread(target=worker, args=(pid,)) for pid in range(player_count)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.time() - started

    clients = [r[0] for r in results if r is not None]
    total_pubs = sum(r[1] for r in results if r is not None)
    succeeded = sum(1 for r in results if r is not None)
    failed = sum(1 for e in errors if e is not None)

    # Late fanout deliveries from other concurrent publishers still land
    # after each player's own plan finishes; drain before reading stats.
    drain_deadline = time.time() + 1.0
    for client in clients:
        client.pump(min(time.time() + 0.2, drain_deadline))

    return RoundResult(
        player_count=player_count,
        succeeded=succeeded,
        failed=failed,
        failure_messages=[e for e in errors if e is not None],
        clients=clients,
        total_pubs=total_pubs,
        elapsed=elapsed,
    )


def print_round_stats(round_result):
    clients = round_result.clients
    total_bytes_sent = sum(c.bytes_sent for c in clients)
    total_bytes_received = sum(c.bytes_received for c in clients)
    total_packets_sent = sum(c.packets_sent for c in clients)
    total_packets_received = sum(c.packets_received for c in clients)
    total_payload_received = sum(len(c.received) for c in clients)

    print(f"  succeeded: {round_result.succeeded}/{round_result.player_count}, "
          f"failed: {round_result.failed}")
    print(f"  elapsed: {round_result.elapsed:.3f}s, pub goals executed: {round_result.total_pubs}")
    print(f"  wire packets: {total_packets_sent} sent, {total_packets_received} received")
    print(f"  wire bytes: {total_bytes_sent} sent, {total_bytes_received} received")
    print(f"  fanout payload bytes received by subscribers: {total_payload_received}")
    if round_result.elapsed > 0:
        throughput = (total_bytes_sent + total_bytes_received) / round_result.elapsed
        print(f"  aggregate wire throughput: {throughput:.0f} bytes/s")

    for client in clients:
        client.close()


def run_ramp(addr, args):
    """Doubles the concurrent player count round over round (a fresh room
    each round, so no state carries over) until a round's failure rate
    crosses --fail-threshold, or --max-players is reached. Reports the last
    round that stayed under threshold as the max sustained concurrent
    count for this local single-shard fabric - not a claim about the
    8,000/10,000-per-server figures in ADR 0008, which describe multi-
    machine sizing this one process was never going to reach."""

    player_count = args.ramp_start
    last_good = 0
    round_num = 0
    while player_count <= args.max_players:
        round_num += 1
        room = f"{args.room}-ramp{round_num}"
        print(f"round {round_num}: {player_count} concurrent players (room={room!r})")
        result = run_round(addr, room, player_count, args.ticks, args.tick_interval)
        print_round_stats(result)
        failure_rate = result.failed / result.player_count
        if failure_rate > args.fail_threshold:
            print(f"round {round_num} failure rate {failure_rate:.0%} exceeds "
                  f"--fail-threshold {args.fail_threshold:.0%}; stopping ramp")
            if result.failure_messages:
                sample = result.failure_messages[0]
                print(f"observed failure mode (sample): {sample}")
            break
        last_good = player_count
        player_count *= 2
    else:
        print(f"reached --max-players {args.max_players} without crossing --fail-threshold")

    print(f"max sustained concurrent players (this local single-shard fabric): {last_good}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=4433)
    parser.add_argument("--room", default="microtraffic")
    parser.add_argument("--players", type=int, default=5, help="microscopic by design")
    parser.add_argument("--ticks", type=int, default=10, help="PUBs per player")
    parser.add_argument("--tick-interval", type=float, default=0.05)
    parser.add_argument("--ramp", action="store_true",
                         help="double concurrent players round over round until failures cross --fail-threshold")
    parser.add_argument("--ramp-start", type=int, default=5)
    parser.add_argument("--max-players", type=int, default=2000)
    parser.add_argument("--fail-threshold", type=float, default=0.1,
                         help="fraction of a round's players that may fail before the ramp stops")
    args = parser.parse_args()
    addr = ("127.0.0.1", args.port)

    if args.ramp:
        run_ramp(addr, args)
        return

    print(f"microtraffic: {args.players} concurrent players, {args.ticks} ticks each, room={args.room!r}")
    result = run_round(addr, args.room, args.players, args.ticks, args.tick_interval)
    print_round_stats(result)


if __name__ == "__main__":
    main()
