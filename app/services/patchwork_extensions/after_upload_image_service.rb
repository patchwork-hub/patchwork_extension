# frozen_string_literal: true

module PatchworkExtensions
  # MEDIA-01: generate and store alt text for an uploaded media attachment.
  # Extracted from NewsmastMastodon::AfterUploadImageService; behavior is
  # unchanged. Inherits the host's top-level BaseService (see
  # spec/support/mastodon_stubs.rb for the standalone fallback).
  class AfterUploadImageService < BaseService
    include RoutingHelper

    def initialize(media_attachment_id)
      @media_attachment = MediaAttachment.find(media_attachment_id)
      @payload = validate_image_url
      @api_service = PatchworkExtensions::AltTextAiApiService.new(payload: @payload)
    end

    def call
      return unless @media_attachment.can_generate_alt?
      return unless check_api_usage_limit
      return unless create_image_at_alttext_ai
      update_image_alt
    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
    end

    private

    def create_image_at_alttext_ai
      @alttext_return = @api_service.create_image
      return false unless @alttext_return && !@alttext_return.has_errors?
      true
    end

    def check_api_usage_limit
      response_body = @api_service.get_account
      return false unless response_body && !response_body.has_errors?
      usage_limit = response_body.usage_limit
      usage = response_body.usage
      if usage < usage_limit
        true
      else
        raise "API usage limit exceeded: #{usage}/#{usage_limit}"
      end
    end

    def update_image_alt
      @media_attachment.reload
      if @alttext_return&.alt_text.present?
        @media_attachment.update_column(:description, @alttext_return.alt_text)
      end
    end

    def validate_image_url
      return {} if @media_attachment.nil?
      image_url = full_asset_url(@media_attachment.file.url(:small))&.remove("posts/")
      { image: { url: image_url } }
    end
  end
end
