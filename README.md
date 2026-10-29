# patchwork_extensions (Gem B)

Organization-specific Mastodon extensions, extracted from the
[`newsmast_mastodon`](../newsmast_mastodon(patchwork)) gem (Gem A) as part of the
two-gem split described in `newsmast_gems_split.md`.

- **Gem A** (`newsmast_mastodon`): reusable Mastodon extensions/overrides.
- **Gem B** (this gem): custom/proprietary features. May build on Gem A, but
  Gem A must never depend on this gem.

Ruby namespace: `PatchworkExtensions`.

## Current features

| ID | Feature | Status |
| --- | --- | --- |
| COMMUNITY-03 | Starter-Pack Discovery | Extracted; pending host verification |
| AUTH-06 | Account Deletion and Locale Preferences | Extracted; verified against host |

## Installation

During split development the host loads both gems from local sibling paths:

```ruby
# patchwork-mastodon(demo)/Gemfile
gem 'newsmast_mastodon', path: '../newsmast_mastodon(patchwork)'
gem 'patchwork_extensions', path: '../patchwork_extensions'
```

(For deployment, switch both to git sources.)

Then:

```bash
cd ../patchwork-mastodon(demo)
bundle install
# No migrations for COMMUNITY-03. Future features:
# bin/rails patchwork_extensions:install:migrations && bin/rails db:migrate
```

Restart the app. The engine mounts itself at `/` automatically.

**Ruby version:** match the host (`.ruby-version` pins 4.0.5). Bundler resolves
gems per Ruby version, so running under a different Ruby than the host produces
"is not yet checked out" / missing-gem errors.

## Endpoints

| Endpoint | Description |
| --- | --- |
| `GET /api/v1/channels/starter_packs_channels` | List starter-pack channels from packaged JSON. |
| `GET /api/v1/channels/:id/starter_packs_detail` | Channel detail plus followers JSON. |
| `POST /api/v1/delete_account` | Password-confirmed self-deletion (suspend + host deletion worker). |
| `DELETE /api/v1/patchwork/account_deletion/:id` | Delete an account by id via the host deletion service. |
| `POST /api/v1/user_locales` | Save the authenticated user's locale (`lang` param). |

Both require an authenticated user with `read`/`write` OAuth scopes, matching
the behavior previously served by `newsmast_mastodon`.

### Starter-pack source selection

Pass `starter_pack_source` to select a dataset: `twt` (default),
`thebristolcable`, `findout`, or `leicestergazette`. Unrecognized values fall
back to `twt`.

## Configuration

```ruby
# config/initializers/patchwork_extensions.rb (host app)
PatchworkExtensions.configure do |config|
  # Override the packaged data location (defaults to the gem's config/data):
  config.starter_pack_data_root = Rails.root.join("config/starter_packs")
end
```

Responses are cached in Redis keyed by namespace and file, validated against
file modification time, with `Cache-Control: public, max-age=86400`.

## Testing

Standalone (engine logic only; host-dependent request specs are skipped):

```bash
cd patchwork_extensions
bundle install
bundle exec rspec
```

Against the real Mastodon fork (verified 2026-10-08: 8 examples, 0 failures):

```bash
cd patchwork_extensions
MASTODON_ROOT="/Users/sayamac/workplace/development/patchwork-mastodon(demo)" \
BUNDLE_GEMFILE="/Users/sayamac/workplace/development/patchwork-mastodon(demo)/Gemfile" \
RAILS_ENV=test bundle exec rspec spec/requests
```

Host-mode requires the host bundle to be installed first
(`cd ../patchwork-mastodon(demo) && bundle install`) and the same Ruby version
as the host.

## Cutover notes

Cutover for COMMUNITY-03 is DONE (2026-10-08): the Gem A `resources :channels`
block is commented out with a `GEM_SPLIT[COMMUNITY-03]` marker, and this gem
serves the endpoints. The engine mounts at `/` via `routes.prepend` — Mastodon's
`*unmatched_route` catch-all makes an appended mount unreachable. Remove the
dormant Gem A controller/data after the verification window.
Track progress in [docs/development/gem-split-implementation-log.md](docs/development/gem-split-implementation-log.md).
