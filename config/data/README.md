# Starter pack data

This directory contains bundled starter-pack JSON files used by this gem.

## Purpose

Each subdirectory contains starter-pack definitions for a deployment context.
These datasets are consumed by Newsmast features that present suggested accounts
or channels.

Current directories:

- `findout/`
- `leicestergazette/`
- `thebristolcable/`
- `twt/`

Each starter-pack directory should include a `PROVENANCE.md` file describing
ownership, source, and update policy for the data in that directory.

## Data ownership and provenance

- Files in this directory are maintained by project maintainers.
- Only include publicly visible account identifiers and metadata required by
  the starter-pack format.
- Do not add private personal data to these files.
- When importing or transforming external data, include attribution and source
  details in the pull request that introduces the change.

## Update requirements

When editing starter-pack data:

1. Document why the change is needed in the pull request.
2. Confirm the accounts or channels are appropriate for public suggestion.
3. Note any external source used to assemble the data.
4. Add or update tests if behavior depends on the changed data.
5. Update that directory's `PROVENANCE.md` when source, owner, or policy changes.

## Removal or correction requests

If you are listed in a starter pack and want to request a correction or removal,
open an issue or contact akp@binarylab.io with details.
