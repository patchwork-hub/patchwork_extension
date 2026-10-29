# frozen_string_literal: true

# MEDIA-02 service specs. These stub Mastodon's HTTP/extraction stack but use
# the real PreviewCard model, so they require the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/services
require "rails_helper"

RSpec.describe PatchworkExtensions::FetchLinkMetadataService do
  before { require_host! }

  let(:service) { described_class.new }
  let(:url) { "https://example.com/page" }

  # Builds a stubbed HTTP response and wires Request to yield it from #perform.
  def stub_html_fetch(final_url:, html: "<html></html>", code: 200, mime_type: "text/html", charset: "utf-8")
    response = double(
      code: code,
      mime_type: mime_type,
      charset: charset,
      truncated_body: html,
      request: double(uri: Addressable::URI.parse(final_url))
    )
    request = double
    allow(Request).to receive(:new).and_return(request)
    allow(request).to receive(:add_headers).and_return(request)
    allow(request).to receive(:perform) do |&block|
      block.call(response)
    end
  end

  def stub_no_metadata!
    allow(FetchOEmbedService).to receive_message_chain(:new, :call).and_return(nil)
    extractor = double(to_preview_card_attributes: {})
    allow(LinkDetailsExtractor).to receive(:new).and_return(extractor)
  end

  describe "URL validation" do
    it "raises InvalidURLError when the URL is blank" do
      expect { service.call("") }.to raise_error(described_class::InvalidURLError, "URL must be present")
      expect { service.call(nil) }.to raise_error(described_class::InvalidURLError, "URL must be present")
    end

    it "raises InvalidURLError for URLs without a host" do
      expect { service.call("not-a-url") }.to raise_error(described_class::InvalidURLError, "URL is not valid")
    end

    it "raises InvalidURLError for non-http(s) schemes" do
      expect { service.call("ftp://example.com/file") }
        .to raise_error(described_class::InvalidURLError, "URL is not valid")
    end

    it "raises InvalidURLError for syntactically invalid URIs" do
      expect { service.call("https://exam ple.com/") }
        .to raise_error(described_class::InvalidURLError)
    end
  end

  describe "restricted destinations" do
    it "raises InvalidURLError when Mastodon host validation rejects the destination" do
      allow(Request).to receive(:new).and_raise(Mastodon::HostValidationError)

      expect { service.call(url) }.to raise_error(described_class::InvalidURLError)
    end
  end

  describe "remote failures" do
    it "raises FetchError on HTTP connection errors" do
      allow(Request).to receive(:new).and_raise(HTTP::ConnectionError.new("connection refused"))

      expect { service.call(url) }.to raise_error(described_class::FetchError, /connection refused/)
    end

    it "raises FetchError when the response is not successful HTML" do
      stub_html_fetch(final_url: url, code: 404)
      stub_no_metadata!

      expect { service.call(url) }.to raise_error(described_class::FetchError, "Unable to fetch the provided URL")
    end

    it "raises FetchError when no preview metadata can be extracted" do
      stub_html_fetch(final_url: url)
      stub_no_metadata!

      expect { service.call(url) }
        .to raise_error(described_class::FetchError, "No preview metadata found for the provided URL")
    end
  end

  describe "caching" do
    it "returns a fresh cached preview card without performing HTTP" do
      PreviewCard.create!(url: url, title: "Cached title", description: "Cached description", type: :link)
      allow(Request).to receive(:new) { raise "HTTP must not be performed for fresh cache entries" }

      result = service.call(url)

      expect(result[:title]).to eq("Cached title")
      expect(result[:description]).to eq("Cached description")
      expect(result[:images]).to eq([])
      expect(result[:url]).to eq(url)
    end

    it "refetches when the cached preview card is stale" do
      card = PreviewCard.create!(url: url, title: "Stale", description: "", type: :link)
      card.update_column(:updated_at, 3.weeks.ago)

      stub_html_fetch(final_url: url)
      allow(FetchOEmbedService).to receive_message_chain(:new, :call).and_return(
        { title: "Fresh title", thumbnail_url: nil, type: "link" }
      )

      result = service.call(url)

      expect(result[:title]).to eq("Fresh title")
    end

    it "saves fetched metadata to preview_cards for future cache hits" do
      stub_html_fetch(final_url: url)
      allow(FetchOEmbedService).to receive_message_chain(:new, :call).and_return(
        { title: "Saved title", thumbnail_url: nil, type: "link" }
      )

      service.call(url)

      card = PreviewCard.find_by(url: url)
      expect(card).to be_present
      expect(card.title).to eq("Saved title")
    end
  end

  describe "extraction" do
    it "returns oEmbed metadata, resolving relative thumbnails against the final URL" do
      stub_html_fetch(final_url: "https://example.com/final")
      allow(FetchOEmbedService).to receive_message_chain(:new, :call).and_return(
        { title: "Video", thumbnail_url: "/thumb.jpg", width: "640", height: "360", type: "video" }
      )
      # Skip Paperclip image download during PreviewCard persistence; the
      # response shape (not DB persistence) is what this example verifies.
      allow(service).to receive(:save_preview_card)

      result = service.call(url)

      expect(result[:title]).to eq("Video")
      expect(result[:images]).to eq([ { src: "https://example.com/thumb.jpg", width: 640, height: 360 } ])
      expect(result[:url]).to eq("https://example.com/final")
    end

    it "falls back to OpenGraph extraction when oEmbed is unavailable" do
      stub_html_fetch(final_url: url)
      allow(FetchOEmbedService).to receive_message_chain(:new, :call).and_return(nil)
      extractor = double(to_preview_card_attributes: {
        title: "OG title",
        description: "OG description",
        image_remote_url: "https://example.com/og.png",
        width: 1200,
        height: 630,
        type: :link
      })
      allow(LinkDetailsExtractor).to receive(:new).and_return(extractor)
      # Skip Paperclip image download during PreviewCard persistence.
      allow(service).to receive(:save_preview_card)

      result = service.call(url)

      expect(result[:title]).to eq("OG title")
      expect(result[:description]).to eq("OG description")
      expect(result[:images]).to eq([ { src: "https://example.com/og.png", width: 1200, height: 630 } ])
    end

    it "uses the final URL after redirects for extraction and the response" do
      stub_html_fetch(final_url: "https://example.com/redirected")
      allow(FetchOEmbedService).to receive_message_chain(:new, :call).and_return(nil)
      extractor = double(to_preview_card_attributes: { title: "Redirected", image_remote_url: nil })
      allow(LinkDetailsExtractor).to receive(:new).and_return(extractor)

      result = service.call(url)

      expect(LinkDetailsExtractor).to have_received(:new).with("https://example.com/redirected", anything, anything)
      expect(result[:url]).to eq("https://example.com/redirected")
    end
  end
end
