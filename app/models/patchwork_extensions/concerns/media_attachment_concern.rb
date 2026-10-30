# frozen_string_literal: true

module PatchworkExtensions
  module Concerns
    # MEDIA-01: AI Alt Text and User Preferences.
    # Extracted from NewsmastMastodon::Concerns::MediaAttachmentConcern.
    # Only the alt-text generation behavior moved; the draft-post
    # (`patchwork_drafted_status`) associations and the attached/unattached
    # scopes stay in Gem A with POST-01.
    module MediaAttachmentConcern
      extend ActiveSupport::Concern

      included do
        IMAGE_ALLOW_TYPES = %w[image/jpeg image/jpg image/png image/gif image/webp image/bmp].freeze

        after_save :call_generate_alt_text_worker,
                   if: -> { ENV["ALT_TEXT_ENABLED"].present? && ENV["ALT_TEXT_ENABLED"].to_s.downcase == "true" }

        def can_generate_alt?
          skip_user_setting = ENV["SKIP_ALT_TEXT_USER_SETTING"].present? && ENV["SKIP_ALT_TEXT_USER_SETTING"].to_s.downcase == "true"
          user_check_passes = true

          unless skip_user_setting
            user_toggle_required = ENV["ALT_TEXT_USER_TOGGLE"].present? && ENV["ALT_TEXT_USER_TOGGLE"].to_s.downcase == "true"
            user_check_passes    = user_toggle_required ? check_alt_text_enabled? : true
          end

          is_valid_content_type? && check_user_desc? && locally_authored? && user_check_passes
        end

        def check_alt_text_enabled?
          user = User.find_by_account_id(account_id)
          user&.alttext_enabled
        end

        def check_user_desc?
          !description.present?
        end

        def is_valid_content_type?
          IMAGE_ALLOW_TYPES.include?(file_content_type)
        end

        def locally_authored?
          return true if remote_url.blank?
          return false if status_id.blank?

          status&.local? || false
        end
      end

      private

      def call_generate_alt_text_worker
        return unless can_generate_alt?

        PatchworkExtensions::GenerateAltTextWorker.perform_async(id)
      end
    end
  end
end
