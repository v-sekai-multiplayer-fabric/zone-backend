// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// fanout_load_client is one binary with two roles, dispatched on argv -
// a CockroachDB-style deployment shape (one homogeneous executable every
// node runs, per the user's explicit preference over FoundationDB's
// heterogeneous role-specific processes coordinated by a separate
// supervisor daemon: https://github.com/v-sekai/cockroach,
// Oxide Computer's maintained CockroachDB fork, cited as the reference).
//
//   fanout_load_client <port> <rampStart> <maxPlayers> <ticks> <roundDeadline> [shardCount]
//     Coordinator role (default). Ramps concurrent player count, doubling
//     on success, by relaunching this same binary as a child OS process
//     per player each round (see spawnWorker/waitForWorkers below) and
//     tallying exit codes - not by running many players as concurrent
//     Flow actors in one process, which crashed (see
//     fanout_load_client.actor.cpp's header comment: 3+ simultaneous
//     independent picoquic_quic_t contexts in one process corrupt memory
//     in the vendored picoquic/mbedtls stack). One process per unit of
//     concurrent work is the same lesson FoundationDB's own production
//     deployment already encodes (one fdbserver process per core,
//     supervised by fdbmonitor) - this just gets there via relaunching
//     one binary instead of a second supervisor tool.
//
//     shardCount > 1 additionally spawns that many picoquic_fanout_server
//     processes (ports <port>..<port>+shardCount-1, sibling binary in the
//     same build directory, unmodified - it already takes its port as a
//     plain CLI argument, so no server-side change was needed for this)
//     and round-robins players across them by playerId. This is the raw
//     "N independent shards" fabric shape: each shard's own room/topic
//     space is disjoint (fanout-core's flat broadcast never crosses
//     shards), not the Hilbert-curve interest/authority model ADR 0008
//     actually calls for - proving raw connection capacity across a
//     fabric, not proving the fabric's eventual real spatial semantics.
//
//   fanout_load_client --worker <port> <playerId> <ticks> <deadlineSeconds>
//     Worker role. Runs exactly one simulated player (runOnePlayer,
//     fanout_load_client.actor.cpp) and exits 0 if it completed every ZPB
//     tick before the deadline, 1 otherwise.
//
//   fanout_load_client --multi <port> <playerCount> <ticks> <deadlineSeconds>
//     Multi-connection role (task M3, docs/decisions/... critical-path
//     work on "maximum players on this computer"). Runs playerCount
//     simulated players multiplexed through ONE picoquic_quic_t and ONE
//     socket in this ONE process (runManyPlayers,
//     fanout_load_client.actor.cpp), not one OS process each - avoids the
//     one-process-per-player coordinator's ephemeral-UDP-port ceiling
//     (this machine: 16384 ports total, system-wide) so a load test can
//     find picoquic_fanout_server's own real capacity instead of the load
//     generator's. Prints "succeeded <n>/<playerCount>" and exits 0 if
//     n == playerCount, 1 otherwise. Standalone - not yet wired into the
//     ramp coordinator above (a separate, later integration).

#include "flow/Platform.h"
#include "flow/TLSConfig.h"
#include "flow/flow.h"
#include "flow/network.h"
#include "flow/genericactors.actor.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char** environ;
#endif

#include "flow/actorcompiler.h" // This must be the last #include.

Future<bool> runOnePlayer(int const& playerId, int const& ticks, uint16_t const& serverPort,
                           double const& deadlineSeconds);
Future<int> runManyPlayers(int const& playerCount, int const& ticks, uint16_t const& serverPort,
                            double const& deadlineSeconds);

namespace {

int g_workerExitCode = 1;

} // namespace

// g_network->run() only drives whatever's scheduled; an unobserved
// exception from runOnePlayer would otherwise vanish silently, leaving
// the reactor idling forever with nothing left pending. wait(ready(f)),
// not wait(f): exceptions are illegal in this repo's flow actor code, so
// f's error must never reach wait() and throw - runOnePlayer's own setup
// failures (throw internal_error()) surface here as isError(), a plain
// non-throwing accessor, not a caught exception.
ACTOR Future<Void> runWorkerThenStop(int playerId, int ticks, uint16_t serverPort, double deadlineSeconds) {
	state Future<bool> result = runOnePlayer(playerId, ticks, serverPort, deadlineSeconds);
	wait(ready(result));
	g_workerExitCode = (!result.isError() && result.get()) ? 0 : 1;
	g_network->stop();
	return Void();
}

void runWorker(uint16_t port, int playerId, int ticks, double deadlineSeconds) {
	platformInit();
	Error::init();
	g_network = newNet2(TLSConfig());
	openTraceFile({}, 10 << 20, 100 << 20, ".", "fanout_load_client_worker");
	Future<Void> done = runWorkerThenStop(playerId, ticks, port, deadlineSeconds);
	g_network->run();
	// _exit(), not return: matches the pattern already established in
	// s7_riscv_actor_test.cpp for a short-lived process that doesn't need
	// its own cross-library static destructors to run cleanly on the way
	// out. Tried as the fix for an intermittent crash in this process
	// (an ASSERT deep in vendored flow/SimpleCounter.cpp's periodic
	// counter dump) - it wasn't: that assertion fires during normal
	// runtime, independent of exit path, and the real fix is
	// flow/patches/0001-simplecounter-skip-invalid-name.patch. Kept
	// anyway since a worker spawned potentially thousands of times per
	// ramp has no reason to pay for teardown it doesn't need.
	_exit(g_workerExitCode);
}

namespace {

int g_multiSucceeded = 0;
int g_multiTotal = 0;

} // namespace

ACTOR Future<Void> runMultiThenStop(int playerCount, int ticks, uint16_t serverPort, double deadlineSeconds) {
	state Future<int> result = runManyPlayers(playerCount, ticks, serverPort, deadlineSeconds);
	wait(ready(result));
	g_multiSucceeded = result.isError() ? 0 : result.get();
	g_multiTotal = playerCount;
	g_network->stop();
	return Void();
}

void runMulti(uint16_t port, int playerCount, int ticks, double deadlineSeconds) {
	platformInit();
	Error::init();
	g_network = newNet2(TLSConfig());
	openTraceFile({}, 10 << 20, 100 << 20, ".", "fanout_load_client_multi");
	Future<Void> done = runMultiThenStop(playerCount, ticks, port, deadlineSeconds);
	g_network->run();
	printf("succeeded %d/%d\n", g_multiSucceeded, g_multiTotal);
	fflush(stdout);
	_exit(g_multiSucceeded == g_multiTotal ? 0 : 1);
}

// --- Coordinator: process spawn/wait, no Flow actors needed - this role
// does no picoquic/socket I/O of its own, only OS process management. ---

namespace {

#if defined(_WIN32)
struct ChildHandle {
	PROCESS_INFORMATION pi{};
};
#else
struct ChildHandle {
	pid_t pid = -1;
};
#endif

std::string quoteArg(const std::string& arg) {
	// Every argument this coordinator passes is a plain number or a
	// filesystem path this file itself computed - none contain spaces or
	// quotes, so unconditional double-quoting is sufficient for both
	// CreateProcess's command-line parsing and a POSIX argv vector (where
	// quoting isn't needed at all, but doesn't hurt to keep args uniform
	// between the two spawn paths).
	return "\"" + arg + "\"";
}

// Shared by spawnWorker (relaunches this same binary) and spawnShardServer
// (launches the sibling picoquic_fanout_server binary) - both just build a
// different argv for an otherwise identical CreateProcess/posix_spawn call.
ChildHandle spawnProcess(const std::string& execPath, const std::vector<std::string>& args) {
	ChildHandle child;
#if defined(_WIN32)
	std::string cmdLine;
	for (size_t i = 0; i < args.size(); i++) {
		if (i > 0) {
			cmdLine += " ";
		}
		cmdLine += quoteArg(args[i]);
	}
	STARTUPINFOA si{};
	si.cb = sizeof(si);
	std::vector<char> cmdLineBuf(cmdLine.begin(), cmdLine.end());
	cmdLineBuf.push_back('\0');
	if (!CreateProcessA(nullptr, cmdLineBuf.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si,
	                     &child.pi)) {
		child.pi.hProcess = nullptr;
	}
#else
	std::vector<char*> argv;
	for (const std::string& a : args) {
		argv.push_back(const_cast<char*>(a.c_str()));
	}
	argv.push_back(nullptr);
	pid_t pid = -1;
	if (posix_spawn(&pid, execPath.c_str(), nullptr, nullptr, argv.data(), environ) == 0) {
		child.pid = pid;
	}
#endif
	return child;
}

ChildHandle spawnWorker(const std::string& execPath, uint16_t port, int playerId, int ticks,
                         double deadlineSeconds) {
	return spawnProcess(execPath, { execPath, "--worker", std::to_string(port), std::to_string(playerId),
	                                 std::to_string(ticks), std::to_string(deadlineSeconds) });
}

std::string dirName(const std::string& path) {
	size_t pos = path.find_last_of("/\\");
	return pos == std::string::npos ? "." : path.substr(0, pos);
}

// picoquic_fanout_server is a sibling binary in the same build directory,
// unmodified - it already takes its port as a plain CLI argument (see
// examples/fanout_server_main.actor.cpp), so no server-side change was
// needed to make it launchable as a shard. Cert/key paths are resolved
// relative to the build directory rather than relying on the child's
// working directory, since spawnProcess doesn't set one.
ChildHandle spawnShardServer(const std::string& loadClientExecPath, uint16_t port) {
	std::string buildDir = dirName(loadClientExecPath);
#if defined(_WIN32)
	std::string serverExec = buildDir + "\\picoquic_fanout_server.exe";
#else
	std::string serverExec = buildDir + "/picoquic_fanout_server";
#endif
	std::string certPath = buildDir + "/../thirdparty/picoquic/certs/secp256r1/cert.pem";
	std::string keyPath = buildDir + "/../thirdparty/picoquic/certs/secp256r1/key.pem";
	return spawnProcess(serverExec, { serverExec, std::to_string(port), certPath, keyPath });
}

bool childIsAlive(const ChildHandle& child) {
#if defined(_WIN32)
	return child.pi.hProcess != nullptr;
#else
	return child.pid > 0;
#endif
}

// Non-blocking poll; returns true and sets *exitedZero once the child has
// exited (any way), false while still running.
bool pollChild(ChildHandle& child, bool* exitedZero) {
#if defined(_WIN32)
	DWORD code = 0;
	if (!GetExitCodeProcess(child.pi.hProcess, &code)) {
		*exitedZero = false;
		return true; // treat an unqueryable handle as done-and-failed
	}
	if (code == STILL_ACTIVE) {
		return false;
	}
	*exitedZero = (code == 0);
	return true;
#else
	int status = 0;
	pid_t r = waitpid(child.pid, &status, WNOHANG);
	if (r == 0) {
		return false;
	}
	*exitedZero = WIFEXITED(status) && WEXITSTATUS(status) == 0;
	return true;
#endif
}

void forceKill(ChildHandle& child) {
#if defined(_WIN32)
	if (child.pi.hProcess != nullptr) {
		TerminateProcess(child.pi.hProcess, 1);
		WaitForSingleObject(child.pi.hProcess, 1000);
	}
#else
	if (child.pid > 0) {
		kill(child.pid, SIGKILL);
		int status = 0;
		waitpid(child.pid, &status, 0);
	}
#endif
}

void closeChild(ChildHandle& child) {
#if defined(_WIN32)
	if (child.pi.hProcess != nullptr) {
		CloseHandle(child.pi.hProcess);
	}
	if (child.pi.hThread != nullptr) {
		CloseHandle(child.pi.hThread);
	}
#endif
}

// Spawns playerCount workers and waits for all of them, up to
// deadlineSeconds total for the round (not per child) - stragglers past
// the deadline are force-killed and counted as failed, so one hung
// connection can't hang the whole ramp. Players round-robin across
// shardPorts by playerId - shardPorts.size()==1 is the single-shard case.
int runRound(const std::string& execPath, const std::vector<uint16_t>& shardPorts, int playerCount, int ticks,
             double deadlineSeconds) {
	std::vector<ChildHandle> children;
	children.reserve(playerCount);
	int spawnFailures = 0;
	for (int i = 0; i < playerCount; i++) {
		uint16_t port = shardPorts[i % shardPorts.size()];
		children.push_back(spawnWorker(execPath, port, i, ticks, deadlineSeconds));
		if (!childIsAlive(children.back())) {
			spawnFailures++;
		}
	}
	if (spawnFailures > 0) {
		fprintf(stderr, "[diag] %d/%d spawnWorker calls failed to produce a live process\n", spawnFailures,
		        playerCount);
		fflush(stderr);
	}

	std::vector<bool> reaped(playerCount, false);
	std::vector<bool> succeeded(playerCount, false);
	auto deadline = std::chrono::steady_clock::now() + std::chrono::duration<double>(deadlineSeconds + 1.0);

	bool allReaped = false;
	while (!allReaped && std::chrono::steady_clock::now() < deadline) {
		allReaped = true;
		for (int i = 0; i < playerCount; i++) {
			if (reaped[i] || !childIsAlive(children[i])) {
				continue;
			}
			bool exitedZero = false;
			if (pollChild(children[i], &exitedZero)) {
				reaped[i] = true;
				succeeded[i] = exitedZero;
				closeChild(children[i]);
			} else {
				allReaped = false;
			}
		}
		if (!allReaped) {
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
	}

	int successCount = 0;
	for (int i = 0; i < playerCount; i++) {
		if (!reaped[i] && childIsAlive(children[i])) {
			forceKill(children[i]);
			closeChild(children[i]);
		} else if (succeeded[i]) {
			successCount++;
		}
	}
	return successCount;
}

void runCoordinator(uint16_t port, int rampStart, int maxPlayers, int ticks, double roundDeadline, int shardCount) {
	platformInit();
	std::string execPath = getExecPath();

	std::vector<ChildHandle> shardServers;
	std::vector<uint16_t> shardPorts;
	if (shardCount <= 1) {
		shardPorts.push_back(port);
	} else {
		printf("spawning %d shard servers on ports %d..%d\n", shardCount, port, port + shardCount - 1);
		fflush(stdout);
		for (int s = 0; s < shardCount; s++) {
			uint16_t shardPort = static_cast<uint16_t>(port + s);
			ChildHandle server = spawnShardServer(execPath, shardPort);
			if (!childIsAlive(server)) {
				fprintf(stderr, "[fatal] failed to spawn shard server on port %d\n", shardPort);
				fflush(stderr);
				continue;
			}
			shardServers.push_back(server);
			shardPorts.push_back(shardPort);
		}
		// No health-check handshake here - a fixed settle time before the
		// first round, matching the gap this session's own manual testing
		// already used between starting picoquic_fanout_server and running
		// a client against it.
		std::this_thread::sleep_for(std::chrono::milliseconds(500));
	}

	int playerCount = rampStart;
	int lastGood = 0;
	int roundNum = 0;
	while (playerCount <= maxPlayers) {
		roundNum++;
		auto roundStart = std::chrono::steady_clock::now();
		int succeeded = runRound(execPath, shardPorts, playerCount, ticks, roundDeadline);
		double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - roundStart).count();
		printf("round %d: %d players across %zu shard(s), %d succeeded, %.2fs elapsed\n", roundNum, playerCount,
		       shardPorts.size(), succeeded, elapsed);
		fflush(stdout);
		double failureRate = 1.0 - (static_cast<double>(succeeded) / playerCount);
		if (failureRate > 0.1) {
			printf("round %d failure rate %.0f%% exceeds 10%%; stopping ramp\n", roundNum, failureRate * 100.0);
			fflush(stdout);
			break;
		}
		lastGood = playerCount;
		playerCount *= 2;
	}
	printf("max sustained concurrent players (%zu shard(s), separate OS processes): %d\n", shardPorts.size(),
	       lastGood);
	fflush(stdout);

	for (ChildHandle& server : shardServers) {
		forceKill(server);
		closeChild(server);
	}
}

} // namespace

int main(int argc, char** argv) {
	if (argc > 1 && std::string(argv[1]) == "--worker") {
		uint16_t port = argc > 2 ? static_cast<uint16_t>(atoi(argv[2])) : 4433;
		int playerId = argc > 3 ? atoi(argv[3]) : 0;
		int ticks = argc > 4 ? atoi(argv[4]) : 5;
		double deadlineSeconds = argc > 5 ? atof(argv[5]) : 10.0;
		runWorker(port, playerId, ticks, deadlineSeconds); // _exit()s internally
	}

	if (argc > 1 && std::string(argv[1]) == "--multi") {
		uint16_t port = argc > 2 ? static_cast<uint16_t>(atoi(argv[2])) : 4433;
		int playerCount = argc > 3 ? atoi(argv[3]) : 100;
		int ticks = argc > 4 ? atoi(argv[4]) : 5;
		double deadlineSeconds = argc > 5 ? atof(argv[5]) : 10.0;
		runMulti(port, playerCount, ticks, deadlineSeconds); // _exit()s internally
	}

	uint16_t serverPort = argc > 1 ? static_cast<uint16_t>(atoi(argv[1])) : 4433;
	int rampStart = argc > 2 ? atoi(argv[2]) : 20;
	int maxPlayers = argc > 3 ? atoi(argv[3]) : 5000;
	int ticks = argc > 4 ? atoi(argv[4]) : 5;
	double roundDeadline = argc > 5 ? atof(argv[5]) : 10.0;
	int shardCount = argc > 6 ? atoi(argv[6]) : 1;
	runCoordinator(serverPort, rampStart, maxPlayers, ticks, roundDeadline, shardCount);
	return 0;
}
