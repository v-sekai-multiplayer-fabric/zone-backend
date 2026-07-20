/-!
# Zone Protocol Constants

Port assignment and packet layout shared by the observer and player.

- Zone server: UDP 7443 locally, UDP 443 externally (Cloudflare)
- Zone backend (Phoenix/Bandit): TCP 443
- Retired wrong default: 17500

CH_INTEREST and CH_PLAYER share the same 100-byte layout:
  header (44 bytes) + payload[0..13] (56 bytes) = 100 bytes
-/

set_option autoImplicit false

-- ---------------------------------------------------------------------------
-- Ports
-- ---------------------------------------------------------------------------

def ZONE_SERVER_PORT_LOCAL    : Nat := 7443
def ZONE_SERVER_PORT_EXTERNAL : Nat := 443
def ZONE_BACKEND_PORT         : Nat := 443
def RETIRED_PORT              : Nat := 17500

theorem zone_server_local_ne_retired :
    ZONE_SERVER_PORT_LOCAL ≠ RETIRED_PORT := by decide

theorem zone_server_local_ne_backend :
    ZONE_SERVER_PORT_LOCAL ≠ ZONE_BACKEND_PORT := by decide

theorem correct_local_port : ZONE_SERVER_PORT_LOCAL = 7443 := by decide

-- ---------------------------------------------------------------------------
-- Packet layout
-- ---------------------------------------------------------------------------

def PACKET_SIZE    : Nat := 100
def HEADER_BYTES   : Nat := 44   -- gid(4)+xyz f64×3(24)+vel i16×3(6)+accel i16×3(6)+hlc(4)
def PAYLOAD_OFFSET : Nat := 44
def PAYLOAD_COUNT  : Nat := 14
def PAYLOAD_BYTES  : Nat := PAYLOAD_COUNT * 4

theorem packet_layout_exact :
    HEADER_BYTES + PAYLOAD_BYTES = PACKET_SIZE := by decide

theorem payload_offset_matches_header :
    PAYLOAD_OFFSET = HEADER_BYTES := by decide

/-- Extra payload payload[1..13] ends exactly at the packet boundary. -/
theorem extra_payload_fits :
    PAYLOAD_OFFSET + PAYLOAD_BYTES = PACKET_SIZE := by decide
