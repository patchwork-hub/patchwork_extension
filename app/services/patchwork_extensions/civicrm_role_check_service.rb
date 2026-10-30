# frozen_string_literal: true

# AUTH-04: CiviCRM group-membership role lookup.
# Extracted from NewsmastMastodon::CivicrmRoleCheckService; request contract,
# group priority order, ENV vars and Result shape are preserved unchanged.
require "httparty"
require "json"
require "uri"

module PatchworkExtensions
  class CivicrmRoleCheckService
    include HTTParty

    class TransientFailure < StandardError; end

    CONTACT_GET_PATH = "/civicrm/ajax/api4/Contact/get"
    GROUP_IDS_IN_PRIORITY_ORDER = [ 15, 16, 3 ].freeze

    Result = Struct.new(:values, :group_id, :transient_error, keyword_init: true)

    def initialize(email, force_remote: false)
      @email = email
      @force_remote = force_remote
    end

    def call
      return empty_result unless force_remote? || feature_enabled?
      return empty_result if @email.blank? || !config_present?

      GROUP_IDS_IN_PRIORITY_ORDER.each do |group_id|
        response = self.class.get(
          endpoint_url,
          headers: request_headers,
          query: { params: request_params(group_id).to_json }
        )
        response_body = response.respond_to?(:body) ? normalize_utf8(response.body) : ""

        unless response.success?
          Rails.logger.error("CiviCRM role check failed: status=#{response.code}")
          return transient_failure_result
        end

        body = response.parsed_response
        body = parse_response_body(response_body) unless body.is_a?(Hash)
        values = response_values(body)
        next if values.empty?

        return Result.new(values: values, group_id: group_id, transient_error: false)
      end

      empty_result
    rescue StandardError => e
      Rails.logger.error("CiviCRM role check failed: #{e.class}")
      transient_failure_result
    end

    private

    def force_remote?
      @force_remote
    end

    def feature_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("CSID_ROLE_ASSIGNMENT_ENABLED", "false"))
    end

    def config_present?
      base_url.present? && auth_token.present?
    end

    def base_url
      raw = ENV.fetch("CIVICRM_BASE_URL", nil).to_s.strip
      return "" if raw.blank?

      candidate = raw.match?(%r{\Ahttps?://}i) ? raw : "https://#{raw}"
      uri = URI.parse(candidate)
      uri.scheme = "https" if uri.port == 443 || uri.scheme.blank?
      uri.to_s.chomp("/")
    rescue URI::InvalidURIError
      ""
    end

    def auth_token
      ENV.fetch("CIVICRM_AUTH_TOKEN", nil).to_s.strip.gsub(/\A'+|'+\z/, "")
    end

    def endpoint_url
      "#{base_url}#{CONTACT_GET_PATH}"
    end

    def request_headers
      {
        "accept" => "application/json, text/plain, */*",
        "x-civi-auth" => formatted_auth_token,
        "x-requested-with" => "XMLHttpRequest",
        "skipinterceptor" => "true"
      }
    end

    def formatted_auth_token
      return auth_token if auth_token.match?(/\ABearer\s+/i)

      "Bearer #{auth_token}"
    end

    def request_params(group_id)
      {
        select: [ "id" ],
        join: [
          [ "Email AS email", "LEFT", [ "email.is_primary", "=", true ] ],
          [ "GroupContact AS group_contact", "LEFT", [ "group_contact.status", "=", "'Added'" ] ]
        ],
        groupBy: [ "id" ],
        where: [
          [ "is_deleted", "=", false ],
          [ "email.email", "=", @email ],
          [ "groups", "IN", [ group_id ] ]
        ]
      }
    end

    def parse_response_body(response_body)
      JSON.parse(response_body)
    rescue JSON::ParserError
      {}
    end

    def normalize_utf8(value)
      value
        .to_s
        .dup
        .force_encoding(Encoding::UTF_8)
        .scrub
    end

    def response_values(body)
      return [] unless body.is_a?(Hash)
      return [] unless body.key?("values") || body.key?(:values)

      values = body["values"] || body[:values]
      values.is_a?(Array) ? values : []
    end

    def empty_result
      Result.new(values: [], group_id: nil, transient_error: false)
    end

    def transient_failure_result
      Result.new(values: [], group_id: nil, transient_error: true)
    end
  end
end
