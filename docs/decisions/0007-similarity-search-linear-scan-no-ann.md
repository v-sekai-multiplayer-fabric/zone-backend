---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: tagging, storage
---

# 0007 similar_assets/2 does a linear cosine-similarity scan, no ANN index yet

## Context

`similar_assets/2` (see [[0006-uro-tagging-module]]) needs to rank
`shared_file_semantic_tags` rows by cosine similarity to a query
vector ([[0005-shared-file-semantic-tags-side-table]]).

## Decision Outcome

Chosen: a **linear scan** — load candidate `hrr_vector` rows, compute
cosine similarity in Elixir, sort, take top-N — rather than standing
up a vector/ANN index (e.g. pgvector) up front.

## Consequences

Good: no new Postgres extension or index-maintenance code needed to
ship the feature; simplest possible implementation to verify
correctness against. Bad: O(n) per similarity query — fine at the
current asset-manifest scale, but will need an ANN index before
roughly 10^3-10^4 rows.

## Confirmation

Not yet run against a live database or exercised end-to-end — blocked
on the same `bcrypt_elixir`/`mix compile` environment gap noted in
[[0003-hrr-pure-elixir-no-nif-no-lean]].
