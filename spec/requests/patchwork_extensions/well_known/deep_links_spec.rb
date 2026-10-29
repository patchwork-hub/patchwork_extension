# frozen_string_literal: true

# UI-03 request specs. These exercise the real Mastodon routing stack, so
# every example requires the host harness:
#
#   MASTODON_ROOT=/path/to/mastodon BUNDLE_GEMFILE=/path/to/mastodon/Gemfile \
#     bundle exec rspec spec/requests
require "rails_helper"

RSpec.describe "PatchworkExtensions well-known deep links", type: :request do
  before { require_host! }

  # Set deep-link ENV vars around each example and restore the originals.
  around do |example|
    original = ENV.to_h.slice(
      "IOS_APP_ID", "IOS_DEEPLINK_PATHS",
      "ANDROID_PACKAGE_NAME", "ANDROID_SHA256_CERT_FINGERPRINTS"
    )
    example.run
  ensure
    %w[IOS_APP_ID IOS_DEEPLINK_PATHS ANDROID_PACKAGE_NAME ANDROID_SHA256_CERT_FINGERPRINTS].each do |key|
      original.key?(key) ? ENV[key] = original[key] : ENV.delete(key)
    end
  end

  describe "GET /.well-known/apple-app-site-association" do
    it "returns the association payload with default paths" do
      ENV["IOS_APP_ID"] = "TEAMID.com.example.app"
      ENV.delete("IOS_DEEPLINK_PATHS")

      get "/.well-known/apple-app-site-association"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to eq(
        "applinks" => {
          "apps" => [],
          "details" => [
            { "appID" => "TEAMID.com.example.app", "paths" => ["/@*", "/@*/*"] }
          ]
        }
      )
      expect(response.headers["Cache-Control"]).to include("public")
    end

    it "honors custom IOS_DEEPLINK_PATHS" do
      ENV["IOS_APP_ID"] = "TEAMID.com.example.app"
      ENV["IOS_DEEPLINK_PATHS"] = "/statuses/*, /@*"

      get "/.well-known/apple-app-site-association"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("applinks", "details", 0, "paths"))
        .to eq(["/statuses/*", "/@*"])
    end

    it "returns 404 when IOS_APP_ID is not configured" do
      ENV.delete("IOS_APP_ID")

      get "/.well-known/apple-app-site-association"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /.well-known/assetlinks.json" do
    it "returns the asset-links payload with all fingerprints" do
      ENV["ANDROID_PACKAGE_NAME"] = "com.example.app"
      ENV["ANDROID_SHA256_CERT_FINGERPRINTS"] = "AA:BB:CC, DD:EE:FF"

      get "/.well-known/assetlinks.json"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to eq(
        [
          {
            "relation" => ["delegate_permission/common.handle_all_urls"],
            "target" => {
              "namespace" => "android_app",
              "package_name" => "com.example.app",
              "sha256_cert_fingerprints" => ["AA:BB:CC", "DD:EE:FF"]
            }
          }
        ]
      )
      expect(response.headers["Cache-Control"]).to include("public")
    end

    it "returns 404 when ANDROID_PACKAGE_NAME is missing" do
      ENV.delete("ANDROID_PACKAGE_NAME")
      ENV["ANDROID_SHA256_CERT_FINGERPRINTS"] = "AA:BB:CC"

      get "/.well-known/assetlinks.json"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when ANDROID_SHA256_CERT_FINGERPRINTS is missing" do
      ENV["ANDROID_PACKAGE_NAME"] = "com.example.app"
      ENV.delete("ANDROID_SHA256_CERT_FINGERPRINTS")

      get "/.well-known/assetlinks.json"

      expect(response).to have_http_status(:not_found)
    end
  end
end
