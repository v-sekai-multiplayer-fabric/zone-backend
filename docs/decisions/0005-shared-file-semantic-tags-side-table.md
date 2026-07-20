---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly to main, no PR review
labels: tagging, storage
---

# 0005 shared_file_semantic_tags as a 1:1 side table, keyed off shared_files

## Context

HRR tag vectors need storage in `zone-backend`. The original plan
guessed an `asset_manifests` table; reading `Uro.StorageController` /
`shared_content.ex` showed the real manifest table is `shared_files`
(`Uro.SharedContent.SharedFile`), with `spawn_baker/1` as the real
Docker baker trigger to repoint later (tracked as open work, not yet
done).

## Decision Outcome

Chosen: a new `shared_file_semantic_tags` table (`shared_file_id` FK,
unique index, `tags` map, `hrr_vector` float array, `hrr_dim`,
`schema_version`), rather than adding columns to `shared_files`
directly — keeps the tagging concept, its own migration history, and
its HRR dependency ([[0003-hrr-pure-elixir-no-nif-no-lean]])
separable from the core upload/bake schema.

## Consequences

Good: additive, no changes to existing `shared_files` rows/queries.
Bad: one more join for anything that wants file + tags together;
linear scan (see [[0007-similarity-search-linear-scan-no-ann]]) caps out
around 10^3-10^4 rows before an ANN index is needed.

## Confirmation

Migration, schema, and context module all parse clean under `elixir -e
Code.string_to_quoted!`. Full `mix compile` not yet run (see the
`bcrypt_elixir` environment gap noted in the HRR MADR);
`Uro.Tagging.tag_asset/2` depends on this table and on `Uro.Hrr` to run
end to end.
