# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Initial engine scaffold for Gem B (`patchwork_extensions`).
- COMMUNITY-03 Starter-Pack Discovery extracted from `newsmast_mastodon`:
  `GET /api/v1/channels/starter_packs_channels` and
  `GET /api/v1/channels/:id/starter_packs_detail`, packaged starter-pack JSON
  data, and modification-time-validated Redis caching.
- Configurable starter-pack data root
  (`PatchworkExtensions.configuration.starter_pack_data_root`) for tests and
  deployment overrides.
- CONV-01 Conversation Lookup and Read State extracted from `newsmast_mastodon`:
  `GET /api/v1/patchwork/conversations/check_conversation` and
  `POST /api/v1/patchwork/conversations/read_all`, preserving the original
  OAuth scopes, response shapes and pagination behavior.
- AUTH-06 Account Deletion and Locale Preferences extracted from
  `newsmast_mastodon`: `POST /api/v1/delete_account`,
  `DELETE /api/v1/patchwork/account_deletion/:id` and
  `POST /api/v1/user_locales`, including the shared API response helper
  concerns and their `api.*` English message keys.
