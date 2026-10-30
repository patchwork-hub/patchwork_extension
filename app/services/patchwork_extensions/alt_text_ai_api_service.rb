# frozen_string_literal: true

module PatchworkExtensions
  # MEDIA-01: AltText.ai API client.
  # Extracted from NewsmastMastodon::AltTextAiApiService; behavior is unchanged.
  class AltTextAiApiService
    require "httparty"
    require "json"

    def initialize(options = {})
      @options = options
      @base_url = ENV["ALT_TEXT_URL"]
      @api_key =  ENV["ALT_TEXT_SECRET"]
      @payload = @options[:payload] if @options.key?(:payload)
    end

    def get_account
      response = make_get_request("account")
      response
    end

    def create_image
      response = make_post_request("images")
      response
    end

    def make_get_request(endpoint)
      base_url = @base_url + endpoint
      headers = {
        "X-API-Key" => @api_key,
        "Content-Type" => "application/json"
      }
      begin
        response = HTTParty.get(base_url, headers: headers)
        resp_body_obj = PatchworkExtensions::AlttextGetAccount.new(JSON.parse(response.body))
        resp_body_obj
      rescue StandardError => e
        Rails.logger.error "Error making GET request: #{e.message}"
      end
    end

    def make_post_request(endpoint)
      base_url = @base_url + endpoint
      headers = {
        "X-API-Key" => @api_key,
        "Content-Type" => "application/json"
      }
      begin
        response = HTTParty.post(base_url,
                                 body: @payload.to_json, headers: headers)
        resp_body_obj = PatchworkExtensions::AlttextCreateImage.new(JSON.parse(response.body))
        resp_body_obj
      rescue StandardError => e
        Rails.logger.error "Error making POST request: #{e.message}"
      end
    end
  end
end
