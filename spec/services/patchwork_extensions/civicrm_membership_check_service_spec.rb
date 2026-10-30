# frozen_string_literal: true

# AUTH-04: standalone-capable spec for the CiviCRM membership check.
# Ported from Gem A's spec/services/newsmast_mastodon/civicrm_membership_check_service_spec.rb.
require "rails_helper"

RSpec.describe PatchworkExtensions::CivicrmMembershipCheckService, type: :service do
  subject(:service) { described_class.new("member@example.org") }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CIVICRM_BASE_URL", nil).and_return("https://csidnet.civicrm.org")
    allow(ENV).to receive(:fetch).with("CIVICRM_AUTH_TOKEN", nil).and_return("my-token")
  end

  context "when membership check feature is disabled" do
    before do
      allow(ENV).to receive(:fetch).with("CSID_MEMBERSHIP_CHECK_ENABLED", "false").and_return("false")
    end

    it "returns valid without making an API request" do
      expect(described_class).not_to receive(:get)

      result = service.call

      expect(result.valid?).to be(true)
    end

    it "calls CiviCRM when forced" do
      response = instance_double("HTTParty::Response", success?: true, parsed_response: { "count" => 1, "values" => [ { "id" => 7 } ] })
      allow(described_class).to receive(:get).and_return(response)

      result = described_class.new("member@example.org", force_remote: true).call

      expect(described_class).to have_received(:get)
      expect(result.valid?).to be(true)
    end
  end

  context "when membership check feature is enabled" do
    before do
      allow(ENV).to receive(:fetch).with("CSID_MEMBERSHIP_CHECK_ENABLED", "false").and_return("true")
    end

    it "returns valid without making API requests for allowlisted emails from env key" do
      allow(ENV).to receive(:fetch).with("CSID_MEMBERSHIP_ALLOWLIST_EMAILS", nil)
        .and_return('["mariana@newsmastfoundation.org", "saskia@newsmastfoundation.org"]')
      allow(described_class).to receive(:get)

      mariana_result = described_class.new("mariana@newsmastfoundation.org").call
      saskia_result = described_class.new("saskia@newsmastfoundation.org").call

      expect(described_class).not_to have_received(:get)
      expect(mariana_result.valid?).to be(true)
      expect(saskia_result.valid?).to be(true)
    end

    it "returns valid when CiviCRM finds at least one contact" do
      response = instance_double("HTTParty::Response", success?: true, parsed_response: {
        "count" => 1,
        "values" => [ { "id" => 7, "user_groups" => [ "CSIDNet Team", "Newsletter sign-up" ] } ]
      })
      allow(described_class).to receive(:get).and_return(response)

      result = service.call

      expect(result.valid?).to be(true)
      expect(result.error_message).to be_nil
      expect(result.user_groups).to eq([ "CSIDNet Team", "Newsletter sign-up" ])
    end

    it "extracts user_groups when values is a hash keyed by contact id" do
      response = instance_double("HTTParty::Response", success?: true, parsed_response: {
        "count" => 1,
        "values" => {
          "123" => { "id" => 123, "user_groups" => "CSIDNet Team, Newsletter sign-up" }
        }
      })
      allow(described_class).to receive(:get).and_return(response)

      result = service.call

      expect(result.valid?).to be(true)
      expect(result.user_groups).to eq([ "CSIDNet Team", "Newsletter sign-up" ])
    end

    it "extracts user_groups across multiple records when first record has none" do
      response = instance_double("HTTParty::Response", success?: true, parsed_response: {
        "count" => 2,
        "values" => {
          "123" => { "id" => 123, "display_name" => "No Groups" },
          "456" => { "id" => 456, "user_groups" => "CSIDNet Team; Research WG" }
        }
      })
      allow(described_class).to receive(:get).and_return(response)

      result = service.call

      expect(result.valid?).to be(true)
      expect(result.user_groups).to eq([ "CSIDNet Team", "Research WG" ])
    end

    it "returns invalid when CiviCRM returns empty values" do
      response = instance_double("HTTParty::Response", success?: true, parsed_response: { "count" => 0, "values" => [] })
      allow(described_class).to receive(:get).and_return(response)

      result = service.call

      expect(result.valid?).to be(false)
      expect(result.error_message).to eq(I18n.t("api.account.errors.membership_not_eligible"))
    end

    it "returns invalid when API request fails" do
      response = instance_double("HTTParty::Response", success?: false, code: 401, body: "unauthorized")
      allow(described_class).to receive(:get).and_return(response)

      result = service.call

      expect(result.valid?).to be(false)
    end

    it "returns invalid on request exceptions" do
      allow(described_class).to receive(:get).and_raise(StandardError.new("timeout"))

      result = service.call

      expect(result.valid?).to be(false)
    end
  end
end
