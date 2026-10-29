# frozen_string_literal: true

module PatchworkExtensions::Api::V1
  # MEDIA-02: Link Previews.
  # Extracted from NewsmastMastodon::Api::V1::UtilitiesController.
  # Preserves the original endpoint URL, response shapes and error statuses.
  # NOTE: intentionally unauthenticated, matching the Gem A original.
  class UtilitiesController < ::Api::BaseController
    def link_preview
      url = params[:url]
      unless url.present?
        return render json: { error: "URL must be present" }, status: :bad_request
      end

      data = PatchworkExtensions::FetchLinkMetadataService.new.call(url)
      render json: data, status: :ok
    rescue PatchworkExtensions::FetchLinkMetadataService::InvalidURLError => e
      render json: { error: e.message }, status: :bad_request
    rescue PatchworkExtensions::FetchLinkMetadataService::FetchError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
