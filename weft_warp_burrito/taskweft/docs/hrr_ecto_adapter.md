# HRR Ecto Adapter

`Taskweft.HRR` is a custom Ecto adapter that replaces SQL semantics with
Holographic Reduced Representations, backed by SQLite for persistence.

---

## Motivation

Standard Ecto adapters store records in relational tables and query them
with exact predicate logic.  Taskweft needs to query planning state by
*semantic similarity* — "find tasks related to this entity", not "find
tasks WHERE entity_id = X".  HRRs let us encode any record as a dense
phase vector, bind field roles into it, and recover approximate field
values via circular convolution.  The result is a store that handles
exact lookups and approximate semantic search within the same Ecto API.

---

## Components

### `Taskweft.HRR.Adapter`

The Ecto adapter shim.  Registers `Ecto.Adapter`, `Ecto.Adapter.Schema`,
`Ecto.Adapter.Queryable`, and `Ecto.Adapter.Transaction` behaviours
conditionally at compile time (`Code.ensure_loaded?`) so the library
compiles without Ecto as a dependency.

Config keys forwarded to `Storage`:

| Key        | Default                       | Purpose               |
|------------|-------------------------------|-----------------------|
| `:hrr_dim` | `1024`                        | HRR vector dimension  |
| `:name`    | `Taskweft.HRR.Storage`        | GenServer name        |
| `:db_path` | `~/.taskweft/<name>.db`       | SQLite file path      |

`update/6` and `insert_all/8` are each wrapped in their own transaction
so the delete+insert pair (update) and multi-row batch (insert_all) are
atomic.

### `Taskweft.HRR.Storage`

SQLite-backed GenServer.  Owns two tables:

```sql
hrr_records (
  source        TEXT,       -- Ecto schema source name
  id            TEXT,       -- record primary key
  fields_json   TEXT,       -- all fields as JSON
  record_vector BLOB,       -- HRR encoding of the record
  PRIMARY KEY (source, id)
)

hrr_bundles (
  source        TEXT PRIMARY KEY,
  bundle_vector BLOB,       -- superposition of all record_vectors
  record_count  INTEGER,
  updated_at    TIMESTAMP
)
```

**Encoding on INSERT**

For each field in the record:

```
role(f)        = hrr_encode_atom("role_<f>", dim)    → phases → bytes
val(v)         = hrr_encode_text(to_string(v), dim)  → phases → bytes
field_binding  = hrr_bind(role(f), val(v))            → bytes
```

All field bindings are superposed into a single `record_vector`:

```
record_vector = hrr_bundle([field_binding₁, field_binding₂, ...])
```

The source-level `bundle_vector` is rebuilt from all `record_vector`s
after every insert or delete (outside transactions), or at outermost
commit (inside transactions).

**Probe operations**

`probe_field(srv, source, field, query_text, opts)` — recovers the
encoded value for a specific field from each record vector and ranks by
cosine similarity to the query:

```
role_bytes    = hrr_phases_to_bytes(hrr_encode_atom("role_<field>", dim))
query_phases  = hrr_encode_text(query_text, dim)
unbound       = hrr_unbind(record_vector, role_bytes)
similarity    = hrr_similarity(hrr_bytes_to_phases(unbound), query_phases)
```

`probe_text(srv, source, query_text, opts)` — compares the query
against whole `record_vector`s without unbinding a specific role:

```
query_phases   = hrr_encode_text(query_text, dim)
record_phases  = hrr_bytes_to_phases(record_vector)
similarity     = hrr_similarity(record_phases, query_phases)
```

Both return `[{similarity_float, fields_map}]` sorted descending, with
results below `:threshold` excluded.

**Transactions**

SQLite `BEGIN` / `COMMIT` / `ROLLBACK` at depth 0; `SAVEPOINT sp{N}` /
`RELEASE` / `ROLLBACK TO` for nested calls.  Bundle rebuilds are
deferred until the outermost commit so probes inside a transaction see
the pre-transaction bundle state.  Calling commit or rollback outside
a transaction returns `{:error, :not_in_transaction}`.

**Public API**

```elixir
Storage.insert(srv, source, id, fields_map)          # :ok
Storage.get(srv, source, id)                         # map | nil
Storage.delete(srv, source, id)                      # :ok
Storage.all(srv, source)                             # [map]
Storage.dim(srv)                                     # pos_integer
Storage.bundle(srv, source)                          # binary | nil
Storage.record_count(srv, source)                    # non_neg_integer (O(1))
Storage.probe_field(srv, source, field, text, opts)  # [{float, map}]
Storage.probe_text(srv, source, text, opts)          # [{float, map}]
Storage.vectors_for_join(srv, source, field)         # [{bytes, map}]
Storage.begin_transaction(srv)                       # :ok
Storage.commit_transaction(srv)                      # :ok | {:error, :not_in_transaction}
Storage.rollback_transaction(srv)                    # :ok | {:error, :not_in_transaction}
Storage.in_transaction?(srv)                         # boolean
```

### `Taskweft.HRR.Query`

Translates Ecto query ASTs into Storage calls.

**WHERE strategies**

| WHERE shape                    | Strategy                             |
|-------------------------------|--------------------------------------|
| none                          | `Storage.all/2`                      |
| single `LIKE`/`ILIKE`         | `Storage.probe_field/5` (HRR cosine) |
| single `==` or `!=`           | `Storage.all/2` + in-memory filter   |
| multiple predicates (any mix) | `Storage.all/2` + in-memory filter   |

For `LIKE`/`ILIKE`, SQL wildcards (`%`, `_`) are stripped from the
pattern before encoding.  The bare search term is what goes into the
HRR encoder.  When a `LIKE` appears alongside other predicates (multi-
WHERE path), it falls back to regex for consistency.

**Joins**

Inner joins are supported.  The join condition selects the strategy:

| `ON` condition   | Strategy                                                |
|------------------|---------------------------------------------------------|
| `a.k == b.k`     | Exact hash join — group right by key, match left        |
| `a.k LIKE b.k`   | HRR semantic join — rank right rows by cosine similarity|
| anything else    | Cross join                                              |

Joined rows are represented as `[left_map, right_map, ...]`; the binding
index in field references selects the correct map.  Unresolvable join
sources produce no rows.  LEFT JOIN is silently treated as INNER JOIN.

**Aggregates**

| Expression      | Computation                                              |
|-----------------|----------------------------------------------------------|
| `count(*)`      | Fast path: reads `record_count` from `hrr_bundles` (O(1))|
| `count(field)`  | Count non-nil values after filter                        |
| `sum(field)`    | Sum numeric field values after filter                    |
| `avg(field)`    | Average numeric field values after filter                |
| `min(field)`    | Minimum field value after filter                         |
| `max(field)`    | Maximum field value after filter                         |

`count(*)` without a WHERE clause or joins reads directly from
`hrr_bundles.record_count` — no scan of `hrr_records`.

ORDER BY, LIMIT, and OFFSET are applied in Elixir after all other
processing.

**Query option**

`:hrr_threshold` (default `0.1`) — minimum cosine similarity for
`probe_field` results.  Pass as the fifth argument to `Repo.all/2`:

```elixir
Repo.all(query, hrr_threshold: 0.3)
```

---

## SQL concept mapping

| SQL concept      | HRR operation                                             |
|------------------|-----------------------------------------------------------|
| Table            | Per-source `hrr_bundles` row (superposition)              |
| INSERT           | `hrr_bundle([hrr_bind(role(f), encode(v)) ...])`          |
| DELETE           | Remove record vector, rebuild bundle                      |
| UPDATE           | DELETE + INSERT (atomic, wrapped in transaction)          |
| SELECT *         | Deserialise JSON from `hrr_records`                       |
| WHERE f = v      | Exact equality after full scan                            |
| WHERE f LIKE %q% | `probe_field` → cosine rank by `encode(q)`                |
| COUNT(*)         | O(1) read from `hrr_bundles.record_count`                 |
| JOIN ON a = b    | Hash join (group right by key)                            |
| JOIN ON a LIKE b | Semantic join via `vectors_for_join` + cosine similarity  |
| BEGIN/COMMIT     | `begin_transaction` / `commit_transaction`                |
| SAVEPOINT        | Nested `begin_transaction` calls                          |

---

## NIF type contract

All HRR NIFs live in `Taskweft.NIF`.  The type boundary matters:

| NIF                       | Input           | Output  |
|---------------------------|-----------------|---------|
| `hrr_encode_atom/2`       | string, integer | phases  |
| `hrr_encode_text/2`       | string, integer | phases  |
| `hrr_phases_to_bytes/1`   | phases          | bytes   |
| `hrr_bytes_to_phases/2`   | bytes, 0        | phases  |
| `hrr_bind/2`              | bytes, bytes    | bytes   |
| `hrr_unbind/2`            | bytes, bytes    | bytes   |
| `hrr_bundle/1`            | [bytes]         | bytes   |
| `hrr_similarity/2`        | phases, phases  | float   |

Phases are Elixir lists of floats (radians).  Bytes are Erlang binaries
(little-endian float64 arrays).  `hrr_bundle` decodes bytes internally,
averages the phase vectors, and re-encodes to bytes.  `hrr_similarity`
operates on phases only — always convert bytes before calling it.

---

## Caveats

- All reads are full table scans (filtered or ranked in Elixir).  For
  large sources, prefer `probe_field` with a non-trivial threshold so
  the ranked result set stays small.
- `LIKE` patterns that reduce to an empty string after wildcard
  stripping (e.g., `%%`) fall back to `:exact` and return all rows.
- Records whose `build_record_vector` fails (e.g., NIF not loaded)
  are stored with a NULL `record_vector` and excluded from probe
  results, but remain accessible via `get/3` and `all/2`.
- LEFT JOIN is silently treated as INNER JOIN.

---

## Test coverage

163 PropCheck properties across four files:

| File                              | Properties | What is tested                                          |
|-----------------------------------|------------|---------------------------------------------------------|
| `hrr_prop_test.exs`               | 16         | NIF contracts: encode, similarity, roundtrip, bind      |
| `hrr_storage_prop_test.exs`       | 30         | Storage: CRUD, probe ranking/threshold/limit, persistence|
| `hrr_query_prop_test.exs`         | 15         | Query: ==, !=, LIKE, ORDER BY, LIMIT, OFFSET, composition|
| `hrr_txn_join_agg_prop_test.exs`  | 25         | Transactions, exact joins, semantic joins, aggregates   |

Key properties:

- **Self-probe**: inserting a record and probing with the actual field
  value yields non-negative similarity.
- **Probe sorted**: all probe results are in descending similarity order.
- **Threshold**: no result has similarity below the configured threshold.
- **`== ∪ !=` = all**: the union of `WHERE f = v` and `WHERE f != v`
  results equals the full table scan.
- **LIMIT + OFFSET**: sliced results match `Enum.drop |> Enum.take`
  on the unsliced result.
- **Persistence**: a record inserted, then the GenServer stopped and
  restarted against the same SQLite file, is still retrievable.
- **Transaction rollback**: records inserted inside a rolled-back
  transaction are not visible after rollback.
- **Nested transactions**: inner savepoint rollback does not affect
  outer transaction data.
- **Exact join**: joined rows have matching key values on both sides.
- **Semantic join threshold**: no joined row has cosine similarity below
  the configured threshold.
- **COUNT(*) fast path**: `count(*)` without WHERE equals `length(all)`.
- **Aggregate consistency**: `min ≤ avg ≤ max` for any non-empty source.
