---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: committed
discussion: N/A — committed directly to main, no PR review
labels: repo-structure
---

# 0010 multiplayer-fabric-generate-secrets converted from a git submodule to a subtree

## Context

`multiplayer-fabric-generate-secrets` was tracked as a git submodule
(`.gitmodules` pointing at
`https://github.com/V-Sekai-fire/multiplayer-fabric-generate-secrets.git`),
pinned at commit `613651a`, and was uninitialized (empty checkout) in
this working copy.

## Decision Outcome

Chosen: convert it to a **git subtree** at the same path, with full
upstream history (no `--squash`) merged into `zone-backend`'s own
history, rather than continuing as a submodule or squash-importing it.

## Consequences

Good: no separate `git submodule update --init` step for anyone
cloning this repo; the script's source ships directly with
`zone-backend` and is editable in place. Bad: `zone-backend`'s commit
log now carries `multiplayer-fabric-generate-secrets`'s full history
(4 upstream commits) merged in; future upstream changes require a
manual `git subtree pull` rather than a submodule bump.

## Confirmation

`git submodule deinit` + `git rm` removed the submodule cleanly
(`.gitmodules` deleted, no `.git/modules` leftover); `git subtree add
--prefix=multiplayer-fabric-generate-secrets <url> main` completed
with `Added dir 'multiplayer-fabric-generate-secrets'`; working tree
clean afterward, `generate-secrets.sh` present on disk.
