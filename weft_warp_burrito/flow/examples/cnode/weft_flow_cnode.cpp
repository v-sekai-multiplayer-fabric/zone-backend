// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// RFD 5's other half: proves a C Node (erl_interface/ei) can register
// as a real peer on the Erlang distribution protocol and exchange
// ordinary messages with a BEAM node, without being a BEAM VM itself -
// the bridge mechanism BEAM-side consumers (taskweft or anything else)
// use to reach the independently-running Flow core, instead of a NIF
// (a NIF can't be a persistent run loop; see RFD 5's own reasoning).
//
// This file does not yet embed Flow's own actor runtime - it is the
// smallest possible proof that the C Node mechanism itself works on
// this machine/toolchain before wiring Flow's run loop behind it.
// Protocol: connects to a named Elixir node, registered-sends a
// 2-tuple {self(), Message} to a process registered as :echo_server
// there, and waits for exactly one reply message, printing it.
#include <ei.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char** argv) {
	if (argc != 4) {
		fprintf(stderr, "usage: %s <target_node@host> <cookie> <message>\n", argv[0]);
		return 1;
	}
	const char* targetNode = argv[1];
	const char* cookie = argv[2];
	const char* message = argv[3];

	if (ei_init() != 0) {
		fprintf(stderr, "ei_init failed\n");
		return 1;
	}

	ei_cnode ec;
	if (ei_connect_init(&ec, "weft_flow_cnode", cookie, /*creation=*/1) < 0) {
		fprintf(stderr, "ei_connect_init failed\n");
		return 1;
	}

	int fd = ei_connect(&ec, const_cast<char*>(targetNode));
	if (fd < 0) {
		fprintf(stderr, "ei_connect to %s failed (fd=%d) - is epmd running and the target node up?\n", targetNode, fd);
		return 1;
	}
	printf("connected to %s as C Node %s\n", targetNode, ei_thisnodename(&ec));

	ei_x_buff request;
	ei_x_new_with_version(&request);
	ei_x_encode_tuple_header(&request, 2);
	ei_x_encode_pid(&request, ei_self(&ec));
	ei_x_encode_string(&request, message);

	if (ei_reg_send(&ec, fd, const_cast<char*>("echo_server"), request.buff, request.index) < 0) {
		fprintf(stderr, "ei_reg_send failed - is a process registered as :echo_server on %s?\n", targetNode);
		ei_x_free(&request);
		return 1;
	}
	ei_x_free(&request);
	printf("sent to :echo_server on %s: \"%s\"\n", targetNode, message);

	erlang_msg msg;
	ei_x_buff reply;
	ei_x_new(&reply);
	if (ei_xreceive_msg(fd, &msg, &reply) < 0) {
		fprintf(stderr, "ei_xreceive_msg failed - no reply received\n");
		ei_x_free(&reply);
		return 1;
	}

	int index = 0;
	int version = 0;
	ei_decode_version(reply.buff, &index, &version);
	int arity = 0;
	if (ei_decode_tuple_header(reply.buff, &index, &arity) == 0 && arity == 2) {
		char tag[MAXATOMLEN];
		char body[1024];
		ei_decode_atom(reply.buff, &index, tag);
		ei_decode_string(reply.buff, &index, body);
		printf("OK: reply from BEAM node %s: {%s, \"%s\"}\n", targetNode, tag, body);
	} else {
		fprintf(stderr, "FAIL: unexpected reply shape\n");
		ei_x_free(&reply);
		return 1;
	}

	ei_x_free(&reply);
	return 0;
}
