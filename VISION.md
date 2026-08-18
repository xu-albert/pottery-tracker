# Vision

`Potter Journal` exists so that a potter's work - every piece, every glaze, every firing - has a private, permanent, beautiful record.
It serves the potter at the wheel and the shelf, one person with clay on their hands and a phone in their pocket.
It owns exactly one thing: the potter's own journal of their pieces, from first throw to final photo.

## The journal is private by construction

The record is the potter's alone: the local database is encrypted, and the cloud copy exists to back up and sync, never to show anyone else.
No account may ever push another account's data, and a sign-out wipes what the device held; violations of this line rank above every feature.
Photos and notes are the potter's property: deleting them must mean deleted, everywhere the app put them.
There are no followers, no feeds, and no audience.

## Data correctness outranks features

A piece that silently fails to sync, resurrects after deletion, or loses an edit is the worst bug the app can have.
Sync is treated as a correctness problem with invariants and tests, not a best-effort convenience.
A migration must carry every past version's database forward; stranding a user's journal is never acceptable.

## Made like pottery

The app about craft is itself made as a craft object: design work is iterated in committed rounds, and every iteration is archived, not just the winner.
Twenty-three animation rounds over a splash mark's footring direction is the standard, not an anecdote.
Polish is verified on real devices, with golden tests pinning what was approved.

## Free means free

The app costs nothing, shows no ads, sells nothing, and holds no feature hostage.
There is no tip jar, no paywall, and no premium tier; sustainability questions are answered by keeping costs small - cleanup, compression, engineering - not by charging potters.

## Ship like a real app

Store guidelines, encryption declarations, crash reporting, CI, and versioned releases are table stakes, not aspirations.
Platform expansion is pragmatic: Android ships with the same data guarantees first and cosmetic nativeness later.

## Scope

It is not a social network, a marketplace, or a portfolio site.
Outward sharing is in vision only as the potter's own act - the planned per-piece share page, an owner-initiated export of their own work - never an audience inside the app.
It is not a studio-management or teaching tool: one potter, one journal.
It is not a general note-taking app: its objects are pieces, materials, firings, and photos.
It does not talk to kilns, and it does not sell pottery.

Full export of the journal - photos, notes, dates, as an open folder usable without the app - is part of the ownership identity, sequenced for later.

A change aligns when it makes the potter's own record richer, safer, or more permanent - a better way to capture, find, or trust what they made.
A change should be resisted when it adds an audience, a price, a second user type, or any path by which one person's work reaches another's account.
