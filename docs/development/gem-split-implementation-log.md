# Gem Split Implementation Log

Started: 2026-10-07.

Running record of the `newsmast_mastodon` (Gem A) → `patchwork_extensions`
(Gem B) extraction. Use this log to diagnose regressions: every entry records
what moved, what must stay identical, and the evidence that it still works.
The feature inventory and ownership decisions live in Gem A's
[gem-feature-checklist.md](../../../newsmast_mastodon(patchwork)/docs/development/gem-feature-checklist.md).

## How To Use This Log

When behavior is wrong after the split:

1. Find the feature entry and compare **Expected behavior** with what you see.
2. Check **Original sources** against **Destination sources** — drift between
   them is the most common cause of regressions.
3. Re-run the listed **Verification commands**; a passing command with skipped
   examples is not evidence.
4. Check the **Cutover state** — duplicate or missing route registration is the
   second most common failure.

Marker convention in Gem A source:

```ruby
# GEM_SPLIT[<feature-id>]: <status; what to do at cutover>
```

## COMMUNITY-03: Starter-Pack Discovery

**Status:** Verified against host (2026-10-08).
**Cutover state:** COMPLETE — Gem A's `resources :channels` routes block is
commented out (marked `GEM_SPLIT[COMMUNITY-03]`), and the host Gemfile loads both
gems from local paths. Gem B serves the endpoints. Remove the Gem A controller,
commented routes block and `config/data` after the verification window.

### Expected behavior (must be identical after the split)

| Aspect | Contract |
| --- | --- |
| List endpoint | `GET /api/v1/channels/starter_packs_channels` → `{ "data": [...] }` |
| Detail endpoint | `GET /api/v1/channels/:id/starter_packs_detail` → `{ "channel": {...}, "followers": [...] }` |
| Auth | Authenticated user + `read`/`write` OAuth scopes |
| Missing list file | List: `200 { "data": [] }`; Detail: `404 { "error": "Channel not found" }` |
| Unknown pack id | `404 { "error": "Channel not found" }` |
| Source selection | `starter_pack_source` param: `twt` (default + fallback), `thebristolcable`, `findout`, `leicestergazette` |
| HTTP caching | `stale?` on file mtime; `expires_in 24.hours, public: true` |
| Redis caching | Key `accounts:starter_pack_<ns>_<ns>_<file>`, mtime-validated, 24h TTL |

### Original sources (Gem A)

- `app/controllers/newsmast_mastodon/api/v1/channels_controller.rb`
- `config/routes.rb` (`resources :channels` block)
- `config/data/{twt,thebristolcable,findout,leicestergazette}/`

### Destination sources (Gem B)

- `app/controllers/patchwork_extensions/api/v1/channels_controller.rb`
- `app/services/patchwork_extensions/starter_pack_data.rb`
- `config/routes.rb`, `config/data/`

### Intentional changes during extraction

- Data root is configurable (`PatchworkExtensions.configuration.starter_pack_data_root`),
  defaulting to Gem B's packaged `config/data`. Gem A's engine root is no longer referenced.
- Data loading moved from the controller into `StarterPackData` so it is unit-testable
  without booting Mastodon. Redis key format unchanged for cache continuity.
- Engine mounts at `/` via `app.routes.append` (Gem A used `prepend`); Mastodon
  defines no `/api/v1/channels` routes, so resolution is unchanged after cutover.

### Verification commands and results

| Date | Command | Result |
| --- | --- | --- |
| 2026-10-07 | `bundle exec rspec` (standalone) | 14 examples, 0 failures, 8 pending (host-gated request specs skip by design) |
| 2026-10-07 | `gem build patchwork_extensions.gemspec` | Builds; all 27 `config/data` files packaged |
| 2026-10-08 | Host boot: `RAILS_ENV=test bundle exec rails runner` in patchwork-mastodon(demo) | Boots with both gems; `patchwork_extensions` engine mounted at `/` |
| 2026-10-08 | Host dispatch: `Rails.application.call(Rack::MockRequest.env_for(...))` | Endpoint reaches Gem B controller; unauthenticated request gets Mastodon's 422 |
| 2026-10-08 | `MASTODON_ROOT=<host> bundle exec rspec spec/requests` (host mode) | 8 examples, 0 failures — list/detail, missing files, unknown packs, auth, source fallback all pass against the real Mastodon host |
| 2026-10-08 | Same command run from the Gem B directory with `BUNDLE_GEMFILE=<host>/Gemfile` | 8 examples, 0 failures (requires matching Ruby version and the host spec_helper for Chewy `:bypass`) |
| 2026-10-08 | `bundle exec rspec` (standalone, re-run after fixes) | 14 examples, 0 failures, 8 pending |

### Problems and resolutions

1. **Engine mounted via `routes.append` was unreachable.** Mastodon's host routes
   end with `match '*unmatched_route', via: :all, to: 'application#raise_not_found'`,
   which swallows everything appended after it. Fixed by mounting with
   `app.routes.prepend` (same as Gem A).
2. **`uninitialized constant Rails` when the gem is required directly.**
   `lib/patchwork_extensions/engine.rb` references `::Rails::Engine`; resolved by
   letting the host boot (`Bundler.require`) load the gem after ActiveSupport,
   and removing the premature manual `require` from `spec/rails_helper.rb`.
3. **Host-mode specs initially passed against stale Gem A routes.** The host
   Gemfile pointed Gem A at the remote git branch, so the local cutover edits had
   no effect and Gem A still served the endpoints. Fixed by using the local path
   source for Gem A during split development.
4. **Auth expectation corrected.** Mastodon's `require_user!` responds 422
   (unprocessable content), not 401, for missing authentication; spec updated.
5. **Broken autoload path.** `File.expand_path("../../app/services", __FILE__)`
   resolved outside the gem root; replaced with `root.join("app", "services")`.
6. **Ruby version mismatch.** The gem directory defaulted to rbenv Ruby 3.4.7
   while the host pins 4.0.5; Bundler resolves per Ruby version, so host-mode
   runs failed with "not yet checked out". Fixed with a `.ruby-version` file
   matching the host.
7. **`Chewy::UndefinedUpdateStrategy` in host-mode specs.** Factories trigger
   Mastodon search-index callbacks; the host's `spec/spec_helper.rb` wraps the
   suite in `Chewy.strategy(:bypass)` (plus seeds and registration-mode
   defaults). Gem B's `spec/rails_helper.rb` now requires the host's
   spec_helper in host mode.

### Rollback

Uncomment the Gem A `GEM_SPLIT[COMMUNITY-03]` routes block in Gem A's
`config/routes.rb` and remove Gem B from the host Gemfile. Redis cache keys are
shared, so no cache flush is needed.

---

## CONV-01: Conversation Lookup and Read State

**Status:** Verified against host (2026-10-09).
**Cutover state:** COMPLETE — Gem A's `resources :conversations` routes block is
commented out (marked `GEM_SPLIT[CONV-01]`), and the host Gemfile loads both
gems from local paths. Gem B serves the endpoints. Remove the Gem A controller
and commented routes block after the verification window.

### Expected behavior (must be identical after the split)

| Aspect | Contract |
| --- | --- |
| Lookup endpoint | `GET /api/v1/patchwork/conversations/check_conversation?target_account_id=<id>` → serialized conversation, or `200 {}` when none exists or the param is blank |
| Read-all endpoint | `POST /api/v1/patchwork/conversations/read_all` → `{ "success": true, "updated_count": <n>, "message": "..." }` |
| Auth | Authenticated user; `read`/`read:statuses` scope for lookup, `write`/`write:conversations` for read-all. `doorkeeper_authorize!` runs before `require_user!`, so missing auth returns 401 (unlike COMMUNITY-03's 422) |
| Account isolation | Both actions are scoped to `current_account`; other accounts' conversations are never read or modified |
| Pagination | Lookup returns at most 1 record (`LIMIT = 1`) via `to_a_paginated_by_id` with `max_id`/`since_id`/`min_id` |

### Original sources (Gem A)

- `app/controllers/newsmast_mastodon/api/v1/patchwork/conversations_controller.rb`
- `config/routes.rb` (`resources :conversations` block inside `namespace :patchwork`)

### Destination sources (Gem B)

- `app/controllers/patchwork_extensions/api/v1/patchwork/conversations_controller.rb`
- `config/routes.rb` (`namespace :patchwork` block)
- `spec/requests/patchwork_extensions/api/v1/patchwork/conversations_spec.rb`

### Intentional changes during extraction

- None to behavior: controller body is copied unchanged. Only the namespace
  changed (`NewsmastMastodon::Api::V1::Patchwork` →
  `PatchworkExtensions::Api::V1::Patchwork`), keeping the URL path
  `/api/v1/patchwork/conversations/...` identical.
- Request specs were strengthened beyond Gem A's version (which only asserted
  200): participant lookup, blank/missing target, account isolation, actual
  `updated_count` values and foreign-account preservation are now covered.
- The pre-existing `read_all` quirk (plain JSON hash rendered with inert
  `each_serializer`/`relationships` options) is preserved verbatim to keep the
  response contract unchanged; clean up separately after verification.

### Verification commands and results

| Date | Command | Result |
| --- | --- | --- |
| 2026-10-09 | `bundle exec rspec` (standalone) | 23 examples, 0 failures, 17 pending (host-gated request specs skip by design) |
| 2026-10-09 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec spec/requests` (host mode) | 17 examples, 0 failures — participant lookup, blank/missing target, account isolation, `updated_count` values, foreign-account preservation and auth all pass against the real Mastodon host |
| 2026-10-09 | Same command, immediate re-run | 17 examples, 0 failures (repeatable; no cross-run residue) |

### Problems and resolutions

1. **Auth status expectation.** `doorkeeper_authorize!` runs before
   `require_user!` in this controller, so unauthenticated requests get 401 from
   Doorkeeper — not the 422 that COMMUNITY-03's controller produces (its
   `require_user!` runs first). Spec asserts 401, matching production behavior.
2. **No transactional fixtures in Gem B's host-mode harness.** Gem B's
   `spec/rails_helper.rb` only required the host's `spec_helper`, never enabling
   `use_transactional_fixtures`, so fabricated data persisted across runs and
   collided with Faker's deterministic per-seed values. Fixed by enabling
   `config.use_transactional_fixtures = true` when ActiveRecord is present
   (matching the host's rails_helper), and cleaning the host test DB once with
   `DatabaseCleaner.clean_with(:deletion)` (seeds reload via the host
   spec_helper's `before(:suite)`).
3. **Serializer id contract.** This host fork's `REST::ConversationSerializer`
   exposes `object.id` (the AccountConversation id), not `conversation_id` as
   upstream Mastodon does. The spec asserts against the AccountConversation id;
   endpoint behavior is unchanged either way since the host serializer is shared.

### Rollback

Uncomment the Gem A `GEM_SPLIT[CONV-01]` routes block in Gem A's
`config/routes.rb` and remove Gem B from the host Gemfile. The feature touches
no Redis keys, migrations or queued jobs, so no other cleanup is needed.

---

## MEDIA-02: Link Previews

**Status:** Verified against host (2026-10-13).
**Cutover state:** COMPLETE — Gem A's `resources :utilities` routes block is
commented out (marked `GEM_SPLIT[MEDIA-02]`), and the host Gemfile loads both
gems from local paths. Gem B serves the endpoint. Remove the Gem A controller,
the commented routes block and Gem A's `FetchLinkMetadataService` after the
verification window.

### Expected behavior (must be identical after the split)

| Aspect | Contract |
| --- | --- |
| Endpoint | `GET /api/v1/utilities/link_preview?url=...` → `200 { title, description, images: [{src, width, height}], url }` |
| Missing `url` param | `400 { "error": "URL must be present" }` |
| Invalid/disallowed URL | `400 { "error": <message> }` (`InvalidURLError`) |
| Fetch/metadata failure | `422 { "error": <message> }` (`FetchError`) |
| Auth | None — the endpoint is intentionally unauthenticated (parity with Gem A) |
| Caching | `preview_cards` row reused when `updated_at` is < 2 weeks old; fetched metadata saved back for future hits |
| Fetching | Mastodon `Request` stack (redirects followed, final URL wins), oEmbed first, OpenGraph fallback |

### Original sources (Gem A)

- `app/controllers/newsmast_mastodon/api/v1/utilities_controller.rb`
- `app/services/newsmast_mastodon/fetch_link_metadata_service.rb`
- `config/routes.rb` (`resources :utilities` block)

### Destination sources (Gem B)

- `app/controllers/patchwork_extensions/api/v1/utilities_controller.rb`
- `app/services/patchwork_extensions/fetch_link_metadata_service.rb`
- `config/routes.rb` (`resources :utilities` block)
- `spec/support/mastodon_stubs.rb` (new shared harness stub, see Problems)

### Intentional changes during extraction

- None to behavior: controller and service bodies are copied unchanged. Only
  the namespaces changed (`NewsmastMastodon::Api::V1` →
  `PatchworkExtensions::Api::V1`, `NewsmastMastodon` → `PatchworkExtensions`),
  keeping the URL path `/api/v1/utilities/link_preview` identical.
- The service still inherits the host's top-level `BaseService` (neither gem
  owns that class); no Gem A code is referenced.
- Specs were added beyond Gem A's version (which only asserted 200 with a
  stubbed service): fetch-level checks for invalid URLs, restricted
  destinations, remote failures, redirects, cache freshness and both
  extraction paths, per the checklist's verification requirement.

### Verification commands and results

| Date | Command | Result |
| --- | --- | --- |
| 2026-10-13 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec spec/requests spec/services` (host mode) | 41 examples, 0 failures — MEDIA-02 contributes 18 (4 request + 14 service); run twice, repeatable |
| 2026-10-13 | `bundle exec rspec` (standalone) | 41 examples, 0 failures, 35 pending (host-gated specs skip by design) |
| 2026-10-13 | `gem build patchwork_extensions.gemspec` | Builds; new controller and service packaged |

### Problems and resolutions

1. **Standalone mode could not load the service class.**
   `RSpec.describe PatchworkExtensions::FetchLinkMetadataService` triggers
   autoload, and the class references `BaseService`, which only exists in the
   host. Fixed by adding a guarded `BaseService` stub in Gem B's
   `spec/support/mastodon_stubs.rb` (mirrors Gem A's `mastodon_stubs.rb`
   approach), required from `spec/rails_helper.rb`; in host mode the real
   class is already defined and the stub is skipped.
2. **Paperclip image download during PreviewCard persistence.** Examples with
   image metadata hit `save_preview_card` → `image_remote_url=` →
   `Request.new`, colliding with the HTTP stub. Response-shape examples now
   stub `save_preview_card`; the no-image "saves to preview_cards" example
   verifies real persistence.

### Rollback

Uncomment the Gem A `GEM_SPLIT[MEDIA-02]` routes block in Gem A's
`config/routes.rb` and remove Gem B from the host Gemfile. The feature touches
no Redis keys, migrations or queued jobs, so no other cleanup is needed.
Cached `preview_cards` rows are shared host data and remain valid either way.

---

## UI-03: Mobile App Association Endpoints

**Status:** Verified against host (2026-10-13).
**Cutover state:** COMPLETE — Gem A's `.well-known` routes block is commented
out (marked `GEM_SPLIT[UI-03]`), and the host Gemfile loads both gems from
local paths. Gem B serves the endpoints. Remove the Gem A controller,
commented routes block and `config/initializers/deep_links.rb` after the
verification window.

### Expected behavior (must be identical after the split)

| Aspect | Contract |
| --- | --- |
| iOS endpoint | `GET /.well-known/apple-app-site-association` → `200 { "applinks": { "apps": [], "details": [{ "appID": ..., "paths": [...] }] } }` |
| Android endpoint | `GET /.well-known/assetlinks.json` → `200 [{ "relation": [...], "target": { "namespace": "android_app", ... } }]` |
| Auth | None — public well-known routes |
| iOS missing config | `404` when `IOS_APP_ID` is blank |
| Android missing config | `404` when `ANDROID_PACKAGE_NAME` or `ANDROID_SHA256_CERT_FINGERPRINTS` is blank |
| Default iOS paths | `["/@*", "/@*/*"]` when `IOS_DEEPLINK_PATHS` is unset |
| List parsing | `IOS_DEEPLINK_PATHS` and `ANDROID_SHA256_CERT_FINGERPRINTS` split on commas, entries stripped |
| HTTP caching | `expires_in 1.day, public: true` |
| Content type | `application/json` |

### Original sources (Gem A)

- `app/controllers/newsmast_mastodon/well_known/deep_links_controller.rb`
- `config/initializers/deep_links.rb`
- `config/routes.rb` (`.well-known` scope block)

### Destination sources (Gem B)

- `app/controllers/patchwork_extensions/well_known/deep_links_controller.rb`
- `config/routes.rb` (`.well-known` scope block)

### Intentional changes during extraction

- `config/initializers/deep_links.rb` was **not** copied. It only wrote
  `Rails.application.config.x.deep_links`, which has no readers anywhere in
  Gem A or the host — the controller reads the four ENV vars directly per
  request. Copying it would add dead configuration; noted here so the Gem A
  initializer is removed deliberately, not forgotten.
- Namespace changed to `PatchworkExtensions::WellKnown::DeepLinksController`;
  behavior, response shapes and status codes are byte-identical.
- Engine mounts at `/` via `app.routes.prepend` (unchanged from prior
  extractions; required because of Mastodon's `*unmatched_route` catch-all).

### Verification commands and results

| Date | Command | Result |
| --- | --- | --- |
| 2026-10-13 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec spec/requests/patchwork_extensions/well_known/deep_links_spec.rb` (host mode) | 6 examples, 0 failures — iOS success/default paths/custom paths/404, Android success/multi-fingerprint/404s |
| 2026-10-13 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec` (host mode, full suite) | 47 examples, 0 failures — no regressions across COMMUNITY-03, CONV-01, MEDIA-02 |
| 2026-10-13 | `bundle exec rspec` (standalone) | 47 examples, 0 failures, 41 pending (host-gated specs skip by design) |
| 2026-10-13 | `gem build patchwork_extensions.gemspec` | Builds; new well-known controller packaged |

### Problems and resolutions

None. ENV vars are read at request time, so specs set/restore them with an
`around` hook instead of stubbing configuration.

### Rollback

Uncomment the Gem A `GEM_SPLIT[UI-03]` routes block in Gem A's
`config/routes.rb` and remove Gem B from the host Gemfile. The feature touches
no Redis keys, migrations, queued jobs or database tables, so no other cleanup
is needed.

---

## AUTH-06: Account Deletion and Locale Preferences

**Status:** Verified against host (2026-10-13).
**Cutover state:** COMPLETE — Gem A's `post "/delete_account"`,
`resources :account_deletion` and `resources :user_locales` routes are
commented out (marked `GEM_SPLIT[AUTH-06]`), and the Gem A request specs were
deleted. Gem B serves the endpoints. Remove the three Gem A controllers and
the commented routes blocks after the verification window.

### Expected behavior (must be identical after the split)

| Aspect | Contract |
| --- | --- |
| Self-deletion endpoint | `POST /api/v1/delete_account` with `password` → `200 { "message": "Resource deleted successfully", "data": {} }`; suspends the account (`origin: :local, block_email: false`) and enqueues host `AccountDeletionWorker` with `{ "reserve_username" => true }` |
| Wrong password | `422 { "message": "Current password is incorrect", "data": {} }`; no suspend, no worker enqueue |
| Id-based deletion endpoint | `DELETE /api/v1/patchwork/account_deletion/:id` → host `DeleteAccountService.new.call(account, reserve_email: false, reserve_username: false)`, then `202 { "message": ..., "data": {} }` |
| Unknown account id | `404 { "error": "Resource not found" }` |
| Locale endpoint | `POST /api/v1/user_locales` with `lang` → `200`, persists `user.locale`, body `{ "message": ..., "data": { "locale": ..., "message": ... } }` |
| Invalid/missing `lang` | `400 { "errors": "Invalid request!", "available_locales": [...] }` |
| Auth | All endpoints need an authenticated user with `read`/`write` scopes. Before-action order differs and is preserved: 422 on `/delete_account` + `/user_locales` (`require_user!` first), 401 on `/patchwork/account_deletion` (`doorkeeper_authorize!` first) |

### Original sources (Gem A)

- `app/controllers/newsmast_mastodon/api/v1/accounts_controller.rb`
- `app/controllers/newsmast_mastodon/api/v1/patchwork/account_deletion_controller.rb`
- `app/controllers/newsmast_mastodon/api/v1/user_locales_controller.rb`
- `app/controllers/newsmast_mastodon/concerns/api_response_helper.rb` and
  `api_custom_response_helper.rb` (shared concerns, duplicated into Gem B)
- `config/locales/*.yml` `api.*` message keys (English values duplicated into
  Gem B's `config/locales/en.yml`)
- `config/routes.rb` (three disabled blocks, marked `GEM_SPLIT[AUTH-06]`)

### Destination sources (Gem B)

- `app/controllers/patchwork_extensions/api/v1/accounts_controller.rb`
- `app/controllers/patchwork_extensions/api/v1/patchwork/account_deletion_controller.rb`
- `app/controllers/patchwork_extensions/api/v1/user_locales_controller.rb`
- `app/controllers/patchwork_extensions/concerns/api_response_helper.rb` and
  `api_custom_response_helper.rb`
- `config/locales/en.yml`, `config/routes.rb`

### Intentional changes during extraction

- The two API response helper concerns were copied verbatim into the
  `PatchworkExtensions::Concerns` namespace; Gem B must not include Gem A
  concerns (Gem A must never depend on Gem B and vice versa for shared code).
- English `api.*` response-message keys were duplicated into Gem B's
  `config/locales/en.yml` so responses survive Gem A's eventual removal. While
  both gems load, the duplicate identical values are harmless.
- No behavior changes otherwise: same URLs, params (`password`, `lang`),
  statuses, response shapes and before-action order.

### Security note (inherited, not introduced)

`DELETE /api/v1/patchwork/account_deletion/:id` has no ownership or admin
check: any authenticated user can delete any account by id. This is the Gem A
contract, preserved unchanged and covered by a spec so the behavior is
explicit. Flagged for follow-up review (same treatment as MEDIA-02's
unauthenticated endpoint).

### Verification commands and results

| Date | Command | Result |
| --- | --- | --- |
| 2026-10-13 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec spec/requests/patchwork_extensions/api/v1/account_deletion_spec.rb spec/requests/patchwork_extensions/api/v1/user_locales_spec.rb` | 11 examples, 0 failures |
| 2026-10-13 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec` (full suite, host mode) | 58 examples, 0 failures |
| 2026-10-13 | `bundle exec rspec` (standalone) | 58 examples, 0 failures, 52 pending (host-gated request specs skip by design) |

### Problems and resolutions

None. The `sign_out` call in `delete_account` is a no-op under token auth and
needed no stubbing; `AccountDeletionWorker.perform_async` is stubbed in specs
so the queue is not touched.

### Rollback

Uncomment the three Gem A `GEM_SPLIT[AUTH-06]` routes blocks in Gem A's
`config/routes.rb` and remove Gem B from the host Gemfile. The feature touches
no Redis keys, migrations, queued jobs or database tables, so no other cleanup
is needed. (Gem A's response helpers and locale keys were left in place, so
Gem A rollback needs no locale changes.)

---

## BOOST-01: Custom Boost-Bot Status Operations

**Status:** Verified
**Cutover state:** Gem B serves the routes; Gem A `custom_statuses` routes
block commented out (2026-10-28); Gem A controller disabled with a
`GEM_SPLIT[BOOST-01]` marker.

### Expected behavior (must be identical after the split)

| Case | Result |
| --- | --- |
| Add without client_id/client_secret | `400 { "error": "Client ID and client secret are required" }` |
| Add/remove with invalid client credentials | `401 { "error": "Invalid client ID or client secret" }` |
| Add without `status_url` | `400 { "error": "Status URL is required" }` |
| Add with no status matching the URL | `404 { "error": "No status found" }` |
| Add with a resolvable status | `200` + `REST::SearchSerializer` body; status id zadded to `feed:mix_channel_local_timeline` |
| Remove without `status_id` | `400 { "error": "Status ID is required" }` |
| Remove with unknown `status_id` | `404` (host `ActiveRecord::RecordNotFound` handling) |
| Remove with a known `status_id` | `200 { "message": "Status removed from custom boost bot timeline" }`; id zrem'd from the same Redis key |
| `CustomBoostBotService#call` | HTTParty POST to `<USERNAME_INSTANCE_URL>/api/v1/custom_statuses/add_custom_boost_bot_status` with JSON body and per-username ENV credentials; returns `false` when the status is missing |

### Original sources (Gem A)

- `app/controllers/newsmast_mastodon/api/v1/custom_statuses/custom_boost_bot_status_controller.rb`
  (disabled, marked `GEM_SPLIT[BOOST-01]`)
- `app/services/newsmast_mastodon/custom_boost_bot_service.rb`
  (RETAINED and still active — see below)
- `config/routes.rb` (`namespace :custom_statuses` block, commented out)
- `spec/requests/custom_boost_bot_status_spec.rb` (deleted at cutover per
  convention; Gem A service spec kept because the Gem A service stays active)

### Destination sources (Gem B)

- `app/controllers/patchwork_extensions/api/v1/custom_statuses/custom_boost_bot_status_controller.rb`
- `app/services/patchwork_extensions/custom_boost_bot_service.rb`
- `config/routes.rb` (`namespace :custom_statuses` block)
- `spec/requests/patchwork_extensions/api/v1/custom_statuses/custom_boost_bot_status_spec.rb`
- `spec/services/patchwork_extensions/custom_boost_bot_service_spec.rb`

### Intentional changes during extraction

- The Gem B controller calls `PatchworkExtensions::CustomTimelineService`
  (extracted under FEED-02) instead of `NewsmastMastodon::CustomTimelineService`.
  Both copies write the same `feed:mix_channel_local_timeline` Redis key, so
  behavior is identical.
- `CustomBoostBotService` was DUPLICATED into Gem B rather than moved: Gem A's
  `ReblogChannelsWorker` (COMMUNITY-02, not yet assigned) still calls
  `NewsmastMastodon::CustomBoostBotService`, and pointing it at Gem B would be
  a Gem A -> Gem B reverse dependency. Same treatment as FEED-02's
  CustomTimelineService. Gem A's copy carries a `GEM_SPLIT[BOOST-01]` retention
  note; remove it when COMMUNITY-02/BOOST-02 migrate.
- No other behavior changes: same URLs, params, statuses, response shapes and
  before-action order.

### Security note (inherited, not introduced)

Both endpoints authenticate with `client_id`/`client_secret` in the POST body:
any valid Doorkeeper application credentials can add/remove boost-bot timeline
entries — no user or admin authorization. This is the Gem A contract, preserved
unchanged and covered by specs. Flagged for follow-up review (same treatment as
MEDIA-02's unauthenticated endpoint and AUTH-06's account_deletion).

### Verification commands and results

| Date | Command | Result |
| --- | --- | --- |
| 2026-10-28 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec spec/requests/patchwork_extensions/api/v1/custom_statuses/custom_boost_bot_status_spec.rb spec/services/patchwork_extensions/custom_boost_bot_service_spec.rb` | 9 examples, 0 failures |
| 2026-10-28 | `MASTODON_ROOT=<host> BUNDLE_GEMFILE=<host>/Gemfile bundle exec rspec` (full suite, host mode) | 71 examples, 0 failures |
| 2026-10-28 | `bundle exec rspec` (standalone) | 71 examples, 0 failures, 62 pending (host-gated request specs skip by design) |
| 2026-10-28 | Gem A: `bundle exec rspec spec/routing/routes_spec.rb spec/services/newsmast_mastodon/custom_boost_bot_service_spec.rb` | 5 examples, 0 failures |

Host note: the host Gemfile had been switched to the git branch
(`mastodon-4.6.5.3`) since FEED-02; it was temporarily restored to local paths
(`gem "newsmast_mastodon", path: ...` + `gem "patchwork_extensions", path: ...`)
for this verification and reverted afterwards.

### Problems and resolutions

- Host Gemfile no longer contained `patchwork_extensions` (moved to a git
  branch for staging), so host-mode Gem B specs failed with `uninitialized
  constant PatchworkExtensions`. Resolved by temporarily restoring the
  documented local-path setup, then reverting.
- Pre-existing CMS-02 spec drift surfaced in the full suite (unrelated to
  BOOST-01): `ghost_subscriptions_spec.rb` referenced `HTTParty` before any
  httparty-requiring class autoloaded (fixed by an explicit `require "httparty"`
  in the spec), and its auth example expected 422 where the current host
  returns 401 (doorkeeper first; expectation updated with a comment, matching
  AUTH-06's documented contract).
- Gem A `spec/routing/routes_spec.rb` still asserted the FEED-02
  `for_you_custom_timeline` and CMS-02 `subscribe_leicester` routes (stale since
  those cutovers); removed per the established cutover convention.

### Rollback

Uncomment the Gem A `GEM_SPLIT[BOOST-01]` `namespace :custom_statuses` block in
Gem A's `config/routes.rb` and remove Gem B from the host Gemfile. The feature
adds no migrations, queued jobs or new Redis keys (it reuses the FEED-02
timeline key), so no other cleanup is needed; Gem A's service copy never left.

---

## Template for the next feature

```markdown
## <ID>: <Name>

**Status:** Assigned | In progress | Extracted | Verified
**Cutover state:** <which gem currently serves the routes/hooks>

### Expected behavior (must be identical after the split)
### Original sources (Gem A)
### Destination sources (Gem B)
### Intentional changes during extraction
### Verification commands and results
### Problems and resolutions
### Rollback
```
