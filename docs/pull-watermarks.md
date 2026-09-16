# Pull watermarks

`SyncService` records a server timestamp read **before** querying any collection.
The marker is committed locally only after the pull finishes. A remote write that
arrives after its collection was queried therefore remains eligible for the next
pull, even when junction reads or photo downloads take seconds.

## Why a pre-query server boundary

Each pull writes `FieldValue.serverTimestamp()` to the account's
`meta/pullBoundary` document, then reads it with `Source.server`. A cached,
unresolved or pending-write value fails the pull. All collection reads still
require the server. The boundary costs one small write and one document read per
pull; it needs no new collection rules or index, and existing account deletion
already removes `meta`.

The maximum timestamp merged across collections would be unsafe: the queries
run sequentially, so a late collection could advance that maximum past an unseen
write to an earlier collection. Separate maxima would require separate cursors
and still cannot safely use the client timestamps on pieces. The pre-query
server boundary also progresses for empty collections and empty accounts.

The account shares one boundary document. If another device replaces it between
this device's write and read, the returned timestamp is still read before this
device starts its collection queries. It is safe to use that value. Later writes
to the document do not change the boundary already held by the running pull.

The marker rounds down to milliseconds and queries use `updatedAt >= marker`.
That deliberately replays the boundary millisecond, covering equal timestamps
and Firestore's finer timestamp precision without accumulating a replay window.

## Pieces and older clients

Photos and materials have server-written `updatedAt` fields. Pieces instead use
client edit times for last-write-wins conflict resolution, including edits from
older installed versions. Filtering pieces by a server-time boundary would still
lose edits from a slow client. Every pull therefore reads all pieces, retaining
the existing full-pull last-write-wins merge so an older remote copy cannot replace
a newer local edit. Junctions already use full reads.

This increases piece document reads per incremental sync. It avoids changing the
existing conflict-resolution clock or requiring every device to upgrade at once.
It does not redefine which edit wins when two devices edit the same piece.

## Existing installs

The existing per-user `lastPulledAt_<uid>` preference now stores the version and
value together as `server-v1:<milliseconds>`. Old integer values are untrusted,
regardless of whether they appear to be in the past or future. They return a
broad-pull sentinel to the notifier rather than `null`: `null` means first sync
and would bulk-upload potentially stale local material copies before recovery.

On the first upgraded sync, normal queued writes are processed, then the service
performs one full pull, including legacy documents without `updatedAt`. Only a
successful pull replaces the old marker. A failed attempt leaves the legacy value
in place and retries broadly next time. Subsequent pulls use the new server
boundary and material/photo queries become incremental. A genuinely new device
with no marker keeps the existing first-sync upload behavior.

Version and timestamp use one preference write, so an interrupted migration
cannot mark an old device-clock value as trusted. Both local-data erase and
pre-app database recovery already clear every preference under this same prefix.
No database schema migration is needed.

## Validation and scope

`test/providers/sync_offline_pull_test.dart` uses real Drift and query filtering
behind a controlled Firestore boundary. The two slow-pull cases, the device-clock
case, and the legacy-future-marker case failed against the original service:
late edits were absent or stale. Additional cases cover equality/precision,
client-timed pieces, newer local edits, boundary failures, interrupted migration,
and unavailable collections. The migration test also checks that the next pull
returns zero old clay documents, rather than repeatedly doing a full pull.

The pending queue and Settings backup claims remain covered by their existing
regressions. Upload-only failure timestamps and indefinite offline waits are
unchanged by this work.
