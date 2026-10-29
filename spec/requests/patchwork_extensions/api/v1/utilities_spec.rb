# frozen_string_literal: true

# MEDIA-02 request specs. These exercise the real Mastodon routing stack, so
# every example requires the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
require "rails_helper"

RSpec.describe "PatchworkExtensions utilities", type: :request do
  before { require_host! }

  describe "GET /api/v1/utilities/link_preview" do
    it "returns link preview data on success (FetchLinkMetadataService stubbed)" do
      fake_data = {
        title: "Example",
        description: "A test page",
        images: [ { src: "https://example.com/image.png", width: 0, height: 0 } ],
        url: "https://example.com"
      }
      service = instance_double(PatchworkExtensions::FetchLinkMetadataService, call: fake_data)
      allow(PatchworkExtensions::FetchLinkMetadataService).to receive(:new).and_return(service)

      get "/api/v1/utilities/link_preview", params: { url: "https://example.com" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(fake_data.deep_stringify_keys)
    end

    it "returns 400 when the url param is missing" do
      get "/api/v1/utilities/link_preview"

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("URL must be present")
    end

    it "returns 400 for an invalid or disallowed URL" do
      service = instance_double(PatchworkExtensions::FetchLinkMetadataService)
      allow(PatchworkExtensions::FetchLinkMetadataService).to receive(:new).and_return(service)
      allow(service).to receive(:call)
        .and_raise(PatchworkExtensions::FetchLinkMetadataService::InvalidURLError, "URL is not valid")

      get "/api/v1/utilities/link_preview", params: { url: "not-a-url" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("URL is not valid")
    end

    it "returns 422 when the remote fetch fails or yields no metadata" do
      service = instance_double(PatchworkExtensions::FetchLinkMetadataService)
      allow(PatchworkExtensions::FetchLinkMetadataService).to receive(:new).and_return(service)
      allow(service).to receive(:call)
        .and_raise(PatchworkExtensions::FetchLinkMetadataService::FetchError, "Unable to fetch the provided URL")

      get "/api/v1/utilities/link_preview", params: { url: "https://example.com" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Unable to fetch the provided URL")
    end
  end
end
