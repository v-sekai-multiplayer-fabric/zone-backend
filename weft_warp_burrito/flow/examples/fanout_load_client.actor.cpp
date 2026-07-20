// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// A Flow-native load client for picoquic_fanout_server: one simulated
// player, a real picoquic client connection speaking repeated ZPB
// (zone-authority/interest publish, ADR 0008; test_picoquic_zpb.py
// proves this same verb end to end at small scale) over its own Flow
// IUDPSocket and picoquic_quic_t context, using the same receiveFrom/
// prepare_next_packet loop shape picoquic_fanout_server.actor.cpp uses
// on the server side.
//
// This exists because the earlier Python/aioquic load script
// (simulate_players_microtraffic.py) hit a real ceiling at 40 concurrent
// threads that turned out to be the test harness's own bottleneck (Python
// GIL contention across OS threads each doing tight blocking-socket
// polls), not the server's.
//
// One quic_t/socket/connection per OS process, not per in-process actor.
// An earlier version ran many players as concurrent Flow actors sharing
// one process: first with one shared picoquic_quic_t, where a burst of
// connections all shared one local 4-tuple and reliably triggered a storm
// of Windows ICMP-port-unreachable/connection-reset notifications; then
// with each player getting its own independent picoquic_quic_t within
// that same process, which crashed outright. 3+ simultaneous independent
// contexts corrupt memory in the vendored picoquic/mbedtls stack (clean
// failure at 3, hard segfault at 4+), a usage pattern nothing else in
// this codebase exercises (every other tool here creates exactly one
// context per process). fanout_load_client_main.actor.cpp's coordinator
// role gets process-level isolation the way FoundationDB does in
// production, one process per unit of concurrent work rather than many
// units sharing one process's memory, by relaunching this same binary as
// a child OS process per player. This matches the user's explicit
// CockroachDB-over-FoundationDB deployment preference: one homogeneous
// executable for every role, not a supervisor coordinating heterogeneous
// role-specific processes. This file is that binary's worker role: it
// only ever handles one player.
//
// Wire protocol (matches picoquic_fanout_server.actor.cpp exactly):
//   ZPB <x> <y> <z>\n<100-byte lean-entity-packet payload>

#include "flow/Platform.h"
#include "flow/TLSConfig.h"
#include "flow/flow.h"
#include "flow/IConnection.h"
#include "flow/IUDPSocket.h"
#include "flow/genericactors.actor.h"

#include "picoquic.h"
#include "picoquic_utils.h"

#include <array>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#endif

#include "flow/actorcompiler.h" // This must be the last #include.

namespace {

constexpr size_t kEntityPacketSize = 100;

enum class PlayerState { Connecting, Publishing, Done, Failed };

struct PlayerCtx {
	int playerId = 0;
	int ticksRemaining = 0;
	PlayerState state = PlayerState::Connecting;
	uint64_t streamId = 0;
};

std::vector<uint8_t> makePayload(int playerId, int tick) {
	std::vector<uint8_t> payload(kEntityPacketSize);
	uint8_t seed = static_cast<uint8_t>((playerId * 1000 + tick) % 256);
	for (size_t i = 0; i < kEntityPacketSize; i++) {
		payload[i] = static_cast<uint8_t>((seed + i) % 256);
	}
	return payload;
}

// ZPB (ADR 0008 zone-authority/interest dispatch, wired into the wire
// protocol in picoquic_fanout_server.actor.cpp) gets no application-level
// reply for a publish that reaches nobody, same as PUB never did. Gating
// each tick on incoming stream data would deadlock every connection for
// the same reason it did before switching from PUB to ZPB: nobody would
// ever send a first publish to trigger anyone else's next one. So every
// tick's ZPB goes out together, once, right when the connection is ready,
// rather than paced by round-trips that don't exist in this protocol.
//
// Position doesn't need to be coordinated across players: the server's
// one default zone (fanout_core_ffi.cpp's startup bootstrap) spans the
// entire Hilbert range, so any (x, y, z) lands every player in the same
// zone regardless of what it is. playerId/tick only need to vary the
// coordinates deterministically, matching makePayload's seed. This is a
// load-generation detail, not a claim about real player positions.
void sendAllTicks(picoquic_cnx_t* cnx, PlayerCtx& player) {
	player.state = PlayerState::Publishing;
	while (player.ticksRemaining > 0) {
		int tick = player.ticksRemaining;
		// vx/vy/vz: this load harness doesn't model real player motion (see
		// the position note above; any coordinate lands in the same
		// bootstrap zone), so it reports zero velocity. A real client
		// reports its actual per-axis speed here, driving the server's
		// k-tick ghost expansion (Fanoutcore/Zone.lean's withinGhostRange).
		std::string zpbHeader = "ZPB " + std::to_string(player.playerId) + " " + std::to_string(tick) + " 0 0 0 0\n";
		std::vector<uint8_t> payload = makePayload(player.playerId, tick);
		picoquic_add_to_stream(cnx, player.streamId, reinterpret_cast<const uint8_t*>(zpbHeader.data()),
		                        zpbHeader.size(), 0);
		picoquic_add_to_stream(cnx, player.streamId, payload.data(), payload.size(), 0);
		player.ticksRemaining--;
	}
	player.state = PlayerState::Done;
}

int loadClientStreamCallback(picoquic_cnx_t* cnx, uint64_t streamId, uint8_t* bytes, size_t length,
                              picoquic_call_back_event_t event, void* callbackCtx, void* /*streamCtx*/) {
	auto* player = reinterpret_cast<PlayerCtx*>(callbackCtx);
	switch (event) {
	case picoquic_callback_almost_ready:
	case picoquic_callback_ready:
		if (player->state == PlayerState::Connecting) {
			player->streamId = 0;
			sendAllTicks(cnx, *player);
		}
		break;
	case picoquic_callback_stream_data:
	case picoquic_callback_stream_fin:
		// Other players' fanout deliveries landing on this stream; nothing
		// to do here beyond acknowledging receipt (picoquic already does
		// that at the transport level). This player's own progression
		// doesn't depend on it.
		(void)bytes;
		(void)length;
		break;
	case picoquic_callback_close:
	case picoquic_callback_application_close:
		if (player->state != PlayerState::Done) {
			player->state = PlayerState::Failed;
		}
		break;
	default:
		break;
	}
	return 0;
}

NetworkAddress sockaddrToNetworkAddress(const sockaddr_storage& addr) {
	const sockaddr_in* in4 = reinterpret_cast<const sockaddr_in*>(&addr);
	return NetworkAddress(IPAddress(ntohl(in4->sin_addr.s_addr)), ntohs(in4->sin_port), true, false);
}

} // namespace

// One simulated player: its own picoquic_quic_t, its own Flow UDP socket,
// one connection. Returns true once all its ZPB ticks have been queued
// and the connection reached picoquic_state_ready; false if
// deadlineSeconds elapses first.
ACTOR Future<bool> runOnePlayer(int playerId, int ticks, uint16_t serverPort, double deadlineSeconds) {
	state PlayerCtx player;
	player.playerId = playerId;
	player.ticksRemaining = ticks;

	state std::array<uint8_t, PICOQUIC_RESET_SECRET_SIZE> resetSeed;
	resetSeed.fill(static_cast<uint8_t>(0x24 + (playerId & 0xff)));

	state picoquic_quic_t* quic = picoquic_create(4,
	                                               nullptr,
	                                               nullptr,
	                                               nullptr,
	                                               "fanout-demo",
	                                               loadClientStreamCallback,
	                                               &player,
	                                               nullptr,
	                                               nullptr,
	                                               resetSeed.data(),
	                                               picoquic_current_time(),
	                                               nullptr,
	                                               nullptr,
	                                               nullptr,
	                                               0);
	if (quic == nullptr) {
		throw internal_error();
	}

	sockaddr_in serverAddr;
	memset(&serverAddr, 0, sizeof(serverAddr));
	serverAddr.sin_family = AF_INET;
	serverAddr.sin_port = htons(serverPort);
	inet_pton(AF_INET, "127.0.0.1", &serverAddr.sin_addr);

	state picoquic_cnx_t* cnx = picoquic_create_cnx(quic,
	                                                 picoquic_null_connection_id,
	                                                 picoquic_null_connection_id,
	                                                 reinterpret_cast<sockaddr*>(&serverAddr),
	                                                 picoquic_current_time(),
	                                                 0,
	                                                 "fanout-load-client",
	                                                 "fanout-demo",
	                                                 1);
	if (cnx == nullptr || picoquic_start_client_cnx(cnx) != 0) {
		picoquic_free(quic);
		throw internal_error();
	}

	state Reference<IUDPSocket> socket = wait(INetworkConnections::net()->createUDPSocket(false));
	// 127.0.0.1, not the 0.0.0.0 wildcard the server binds to: with both
	// ends wildcard-bound, loopback replies from picoquic_fanout_server
	// were never observed arriving back reliably, even though the server
	// was confirmed listening and receiving. Binding the client to the
	// specific loopback address, as test_picoquic_fanout.py's proven
	// aioquic client already does, fixed it.
	socket->bind(NetworkAddress(IPAddress(0x7F000001u), 0, true, false));

	// PICOQUIC_MAX_PACKET_SIZE, not some larger round number: picoquic's own
	// internal packet buffers (e.g. picoquic_stream_data_node_t::data) are
	// fixed at exactly this size, so advertising more receive capacity than
	// that lets an over-length datagram overflow picoquic's internal decrypt
	// buffer. This was a real heap-corruption bug found via lldb (crash
	// trapped inside picoquic_remove_header_protection_inner, called from
	// picoquic_incoming_packet, only manifesting once enough connections/
	// traffic made an over-1536-byte packet likely).
	state std::array<uint8_t, PICOQUIC_MAX_PACKET_SIZE> recvBuf;
	state std::array<uint8_t, PICOQUIC_MAX_PACKET_SIZE> sendBuf;
	state NetworkAddress sender;
	state Future<int> recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
	state double startTime = now();

	loop {
		if (player.state == PlayerState::Done || player.state == PlayerState::Failed ||
		    now() - startTime > deadlineSeconds) {
			break;
		}

		state uint64_t currentTime = static_cast<uint64_t>(now() * 1e6);
		int64_t wakeDelayUs = picoquic_get_next_wake_delay(quic, currentTime, 1000000);
		state double wakeDelayS = wakeDelayUs <= 0 ? 0.0 : static_cast<double>(wakeDelayUs) / 1e6;

		choose {
			// wait(ready(recvF)), not wait(recvF): exceptions are illegal in
			// this repo's flow actor code, so a recv error must never reach
			// wait() and throw. ready() (flow/genericactors.actor.h) always
			// resolves once recvF does, success or error, and recvF's own
			// isError()/getError() are plain non-throwing accessors.
			when(wait(ready(recvF))) {
				if (recvF.isError()) {
					// Windows surfaces an ICMP port-unreachable for a prior
					// datagram as a connection-reset on this socket's next
					// recv, even though UDP itself is connectionless.
					// test_picoquic_fanout.py and
					// picoquic_fanout_server.actor.cpp both already work
					// around the identical thing on their own sockets.
					// Harmless for a QUIC client that keeps retransmitting:
					// drop it and keep receiving.
					recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
				} else {
					int n = recvF.get();
					sockaddr_in addrFrom;
					memset(&addrFrom, 0, sizeof(addrFrom));
					addrFrom.sin_family = AF_INET;
					addrFrom.sin_port = htons(sender.port);
					addrFrom.sin_addr.s_addr = htonl(sender.ip.isV4() ? sender.ip.toV4() : 0u);

					sockaddr_in addrTo;
					memset(&addrTo, 0, sizeof(addrTo));
					addrTo.sin_family = AF_INET;

					picoquic_incoming_packet(quic,
					                          recvBuf.data(),
					                          static_cast<size_t>(n),
					                          reinterpret_cast<sockaddr*>(&addrFrom),
					                          reinterpret_cast<sockaddr*>(&addrTo),
					                          0,
					                          0,
					                          static_cast<uint64_t>(now() * 1e6));
					recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
				}
			}
			when(wait(delay(wakeDelayS))) {
			}
		}

		loop {
			size_t sendLength = 0;
			sockaddr_storage peerAddr;
			sockaddr_storage localAddr;
			int ifIndex = 0;
			picoquic_connection_id_t logCid;
			picoquic_cnx_t* lastCnx = nullptr;
			int ret = picoquic_prepare_next_packet(quic,
			                                        static_cast<uint64_t>(now() * 1e6),
			                                        sendBuf.data(),
			                                        sendBuf.size(),
			                                        &sendLength,
			                                        &peerAddr,
			                                        &localAddr,
			                                        &ifIndex,
			                                        &logCid,
			                                        &lastCnx);
			if (ret != 0 || sendLength == 0) {
				break;
			}
			state NetworkAddress peer = sockaddrToNetworkAddress(peerAddr);
			state Future<int> sendF = socket->sendTo(sendBuf.data(), sendBuf.data() + sendLength, peer);
			wait(ready(sendF));
			if (sendF.isError()) {
				TraceEvent(SevWarn, "LoadClientSendError").error(sendF.getError());
			}
		}
	}

	bool succeeded = player.state == PlayerState::Done;

	// A graceful close before the worker process exits (runWorker calls
	// _exit() right after this returns, with no other opportunity to
	// notify the peer) was tried here and measured to make scaling
	// noticeably worse: round3->4 elapsed-time ratio rose to 10.7x
	// (vs 4.6x without it), and the ramp failed a full round earlier.
	// A per-worker blocking close/drain sequence (up to 4 sequential
	// prepare+wait(ready(sendF)) cycles) adds real serial latency that
	// compounds across every worker in a round as round size grows: the
	// intended fix for stale-entity accumulation cost more than it saved.
	// Left as a plain picoquic_delete_cnx (no wire-level close attempt)
	// until a genuinely cheap way to notify the server exists. The
	// server's own idle timeout already reclaims the entity eventually,
	// just not promptly.
	picoquic_delete_cnx(cnx);
	picoquic_free(quic);
	return succeeded;
}

// Many simulated players multiplexed through ONE picoquic_quic_t and ONE
// Flow UDP socket in this ONE process, not many OS processes. This is
// the design runOnePlayer's own header comment describes as abandoned
// for being unreliable at high burst counts (all connections sharing one
// local 4-tuple triggered a storm of Windows ICMP-port-unreachable/
// connection-reset notifications). That diagnosis turned out to be a
// fixable client-side reliability bug, not a fundamental flaw: binding
// to 127.0.0.1 instead of the 0.0.0.0 wildcard, and treating
// connection_failed as routine instead of fatal (both already applied in
// runOnePlayer above), were enough. It never crashed the process the way
// sharing multiple independent picoquic_quic_t *contexts* did (3+ in one
// process corrupts memory in the vendored picoquic/mbedtls stack);
// multiple *connections* in one context was always safe, just unreliable
// until these fixes landed.
//
// This exists because the one-process-per-player design (CockroachDB-
// style, runOnePlayer/the coordinator) traded the multi-context crash for
// a different ceiling: this machine's ephemeral UDP port range
// (49152-65535, 16384 ports total, shared system-wide) hard-caps how many
// worker processes can each bind their own ephemeral port. That ceiling
// belongs to the load-generation *methodology*, not to
// picoquic_fanout_server: measuring the server's real capacity on this
// machine means using a load generator that doesn't hit a different
// limit first. Many players sharing one socket needs only one ephemeral
// port for however many are hosted in this process.
ACTOR Future<int> runManyPlayers(int playerCount, int ticks, uint16_t serverPort, double deadlineSeconds) {
	state std::vector<PlayerCtx> players(playerCount);
	state std::array<uint8_t, PICOQUIC_RESET_SECRET_SIZE> resetSeed;
	resetSeed.fill(0x5a);

	state picoquic_quic_t* quic = picoquic_create(static_cast<uint32_t>(playerCount) + 4,
	                                               nullptr,
	                                               nullptr,
	                                               nullptr,
	                                               "fanout-demo",
	                                               loadClientStreamCallback,
	                                               nullptr,
	                                               nullptr,
	                                               nullptr,
	                                               resetSeed.data(),
	                                               picoquic_current_time(),
	                                               nullptr,
	                                               nullptr,
	                                               nullptr,
	                                               0);
	if (quic == nullptr) {
		throw internal_error();
	}

	sockaddr_in serverAddr;
	memset(&serverAddr, 0, sizeof(serverAddr));
	serverAddr.sin_family = AF_INET;
	serverAddr.sin_port = htons(serverPort);
	inet_pton(AF_INET, "127.0.0.1", &serverAddr.sin_addr);

	state std::vector<picoquic_cnx_t*> cnxs(playerCount, nullptr);
	for (int i = 0; i < playerCount; i++) {
		players[i].playerId = i;
		players[i].ticksRemaining = ticks;
		picoquic_cnx_t* cnx = picoquic_create_cnx(quic,
		                                           picoquic_null_connection_id,
		                                           picoquic_null_connection_id,
		                                           reinterpret_cast<sockaddr*>(&serverAddr),
		                                           picoquic_current_time(),
		                                           0,
		                                           "fanout-load-client",
		                                           "fanout-demo",
		                                           1);
		if (cnx == nullptr) {
			continue;
		}
		picoquic_set_callback(cnx, loadClientStreamCallback, &players[i]);
		if (picoquic_start_client_cnx(cnx) == 0) {
			cnxs[i] = cnx;
		}
	}

	state Reference<IUDPSocket> socket = wait(INetworkConnections::net()->createUDPSocket(false));
	socket->bind(NetworkAddress(IPAddress(0x7F000001u), 0, true, false));

	// PICOQUIC_MAX_PACKET_SIZE, not some larger round number: picoquic's own
	// internal packet buffers (e.g. picoquic_stream_data_node_t::data) are
	// fixed at exactly this size, so advertising more receive capacity than
	// that lets an over-length datagram overflow picoquic's internal decrypt
	// buffer. This was a real heap-corruption bug found via lldb (crash
	// trapped inside picoquic_remove_header_protection_inner, called from
	// picoquic_incoming_packet, only manifesting once enough connections/
	// traffic made an over-1536-byte packet likely).
	state std::array<uint8_t, PICOQUIC_MAX_PACKET_SIZE> recvBuf;
	state std::array<uint8_t, PICOQUIC_MAX_PACKET_SIZE> sendBuf;
	state NetworkAddress sender;
	state Future<int> recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
	state double startTime = now();

	loop {
		bool allDone = true;
		for (const PlayerCtx& p : players) {
			if (p.state != PlayerState::Done && p.state != PlayerState::Failed) {
				allDone = false;
				break;
			}
		}
		if (allDone || now() - startTime > deadlineSeconds) {
			break;
		}

		// Drain everything picoquic already has ready to send BEFORE
		// deciding whether to wait at all: this is what actually clears
		// the "something due now" condition, so checking
		// picoquic_get_next_wake_delay before draining could see a stale
		// <=0 result and spin the outer loop with no real wait between
		// iterations. Previously papered over with a delay(0.0)/delay
		// floor, both of which either leaked (unbounded re-listen on a
		// still-pending recvF racing an instantly-ready timer) or, once
		// the wait was removed outright without draining first, busy-spun
		// with no yield point at all (a fast stack overflow, no ASan
		// report). Draining first means the only remaining "nothing to do
		// right now" case is genuinely nothing to do, so a wait is always
		// warranted afterward.
		loop {
			size_t sendLength = 0;
			sockaddr_storage peerAddr;
			sockaddr_storage localAddr;
			int ifIndex = 0;
			picoquic_connection_id_t logCid;
			picoquic_cnx_t* lastCnx = nullptr;
			int ret = picoquic_prepare_next_packet(quic,
			                                        static_cast<uint64_t>(now() * 1e6),
			                                        sendBuf.data(),
			                                        sendBuf.size(),
			                                        &sendLength,
			                                        &peerAddr,
			                                        &localAddr,
			                                        &ifIndex,
			                                        &logCid,
			                                        &lastCnx);
			if (ret != 0 || sendLength == 0) {
				break;
			}
			state NetworkAddress peer = sockaddrToNetworkAddress(peerAddr);
			state Future<int> sendF = socket->sendTo(sendBuf.data(), sendBuf.data() + sendLength, peer);
			wait(ready(sendF));
			if (sendF.isError()) {
				TraceEvent(SevWarn, "LoadClientMultiSendError").error(sendF.getError());
			}
		}

		state uint64_t currentTime = static_cast<uint64_t>(now() * 1e6);
		int64_t wakeDelayUs = picoquic_get_next_wake_delay(quic, currentTime, 1000000);

		if (wakeDelayUs > 0) {
			// A real future wake time: race it against recvF exactly
			// once, so recvF gets exactly one live listener at a time.
			double wakeDelayS = static_cast<double>(wakeDelayUs) / 1e6;
			choose {
				when(wait(ready(recvF))) {
					if (recvF.isError()) {
						recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
					} else {
						int n = recvF.get();
						sockaddr_in addrFrom;
						memset(&addrFrom, 0, sizeof(addrFrom));
						addrFrom.sin_family = AF_INET;
						addrFrom.sin_port = htons(sender.port);
						addrFrom.sin_addr.s_addr = htonl(sender.ip.isV4() ? sender.ip.toV4() : 0u);

						sockaddr_in addrTo;
						memset(&addrTo, 0, sizeof(addrTo));
						addrTo.sin_family = AF_INET;

						picoquic_incoming_packet(quic,
						                          recvBuf.data(),
						                          static_cast<size_t>(n),
						                          reinterpret_cast<sockaddr*>(&addrFrom),
						                          reinterpret_cast<sockaddr*>(&addrTo),
						                          0,
						                          0,
						                          static_cast<uint64_t>(now() * 1e6));
						recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
					}
				}
				when(wait(delay(wakeDelayS))) {
				}
			}
		} else {
			// Drained everything and picoquic still reports nothing due
			// in the future (e.g. all connections are simply idle,
			// waiting on the peer). The only remaining real event source
			// is recvF itself, waited on directly with no fabricated
			// timer, so this always yields to the reactor instead of
			// spinning.
			wait(ready(recvF));
			if (recvF.isError()) {
				recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
			} else {
				int n = recvF.get();
				sockaddr_in addrFrom;
				memset(&addrFrom, 0, sizeof(addrFrom));
				addrFrom.sin_family = AF_INET;
				addrFrom.sin_port = htons(sender.port);
				addrFrom.sin_addr.s_addr = htonl(sender.ip.isV4() ? sender.ip.toV4() : 0u);

				sockaddr_in addrTo;
				memset(&addrTo, 0, sizeof(addrTo));
				addrTo.sin_family = AF_INET;

				picoquic_incoming_packet(quic,
				                          recvBuf.data(),
				                          static_cast<size_t>(n),
				                          reinterpret_cast<sockaddr*>(&addrFrom),
				                          reinterpret_cast<sockaddr*>(&addrTo),
				                          0,
				                          0,
				                          static_cast<uint64_t>(now() * 1e6));
				recvF = socket->receiveFrom(recvBuf.data(), recvBuf.data() + recvBuf.size(), &sender);
			}
		}
	}

	state int succeeded = 0;
	for (const PlayerCtx& p : players) {
		if (p.state == PlayerState::Done) {
			succeeded++;
		}
	}
	for (picoquic_cnx_t* cnx : cnxs) {
		if (cnx != nullptr) {
			picoquic_delete_cnx(cnx);
		}
	}
	picoquic_free(quic);
	return succeeded;
}
