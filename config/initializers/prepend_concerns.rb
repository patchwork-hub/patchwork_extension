# frozen_string_literal: true

# Wire Gem B concerns into host Mastodon classes during reload (same pattern
# as Gem A's config/initializers/prepend_concerns.rb).
Rails.application.config.to_prepare do
  # Skip when running in the dummy app (Mastodon host classes not present)
  next unless defined?(MediaAttachment)

  # --- Status / MediaAttachment ---
  # MEDIA-01: AI Alt Text — extracted from Gem A's MediaAttachmentConcern.
  # Gem A's copy keeps only the draft-post associations (POST-01); its
  # alt-text callback is disabled there so the worker is not queued twice.
  MediaAttachment.include(PatchworkExtensions::Concerns::MediaAttachmentConcern)

  # --- Accounts ---
  # AUTH-04: CiviCRM membership gate, community-admin creation and role
  # assignment enqueue on signup — extracted from Gem A's AccountsCreation
  # concern. Gem A's prepend is disabled at cutover so the create override is
  # not applied twice.
  if defined?(Api::V1::AccountsController)
    Api::V1::AccountsController.prepend(PatchworkExtensions::Concerns::AccountsCreation)
  end
end
