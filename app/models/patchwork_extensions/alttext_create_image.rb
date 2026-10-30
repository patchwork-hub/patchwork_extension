# frozen_string_literal: true

module PatchworkExtensions
  # MEDIA-01: response wrapper for the AltText.ai "images" endpoint.
  # Extracted from NewsmastMastodon::AlttextCreateImage; behavior is unchanged.
  class AlttextCreateImage
    attr_accessor :asset_id, :url, :alt_text, :alt_texts, :metadata, :created_at, :errors, :error_code

    def initialize(response_hash = {})
      @asset_id   = response_hash["asset_id"]
      @url        = response_hash["url"]
      @alt_text   = response_hash["alt_text"]
      @alt_texts  = response_hash["alt_texts"]
      @metadata   = response_hash["metadata"]
      @created_at = response_hash["created_at"]
      @errors     = response_hash["errors"]
      @error_code = response_hash["error_code"]
    end

    def has_errors?
      @error_code.present? || @errors.present?
    end
  end
end
