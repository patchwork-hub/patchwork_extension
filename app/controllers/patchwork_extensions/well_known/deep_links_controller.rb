# frozen_string_literal: true

module PatchworkExtensions
  module WellKnown
    # UI-03: Mobile App Association Endpoints.
    # Extracted from NewsmastMastodon::WellKnown::DeepLinksController.
    # Serves deep link configuration files for iOS Universal Links and Android
    # App Links. These endpoints require no authentication and are served as
    # public JSON.
    #
    # Configuration is done exclusively via environment variables:
    #   iOS:     IOS_APP_ID, IOS_DEEPLINK_PATHS
    #   Android: ANDROID_PACKAGE_NAME, ANDROID_SHA256_CERT_FINGERPRINTS
    class DeepLinksController < ActionController::Base # rubocop:disable Rails/ApplicationController
      def apple_app_site_association
        ios_app_id = ENV["IOS_APP_ID"]

        if ios_app_id.blank?
          head :not_found
          return
        end

        paths = if ENV["IOS_DEEPLINK_PATHS"].present?
                  ENV["IOS_DEEPLINK_PATHS"].split(",").map(&:strip)
                else
                  ["/@*", "/@*/*"]
                end

        response_body = {
          applinks: {
            apps: [],
            details: [
              {
                appID: ios_app_id,
                paths: paths
              }
            ]
          }
        }

        expires_in 1.day, public: true
        render json: response_body, content_type: "application/json"
      end

      def asset_links
        package_name = ENV["ANDROID_PACKAGE_NAME"]
        fingerprints_raw = ENV["ANDROID_SHA256_CERT_FINGERPRINTS"]

        if package_name.blank? || fingerprints_raw.blank?
          head :not_found
          return
        end

        fingerprints = fingerprints_raw.split(",").map(&:strip)

        response_body = [
          {
            relation: ["delegate_permission/common.handle_all_urls"],
            target: {
              namespace: "android_app",
              package_name: package_name,
              sha256_cert_fingerprints: fingerprints
            }
          }
        ]

        expires_in 1.day, public: true
        render json: response_body, content_type: "application/json"
      end
    end
  end
end
