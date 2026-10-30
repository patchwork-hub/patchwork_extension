# frozen_string_literal: true

# AUTH-04: standalone-capable spec for the CiviCRM role check.
# Ported from Gem A's spec/services/newsmast_mastodon/civicrm_role_check_service_spec.rb.
require "rails_helper"

RSpec.describe PatchworkExtensions::CivicrmRoleCheckService, type: :service do
  subject(:service) { described_class.new("member@example.org") }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CIVICRM_BASE_URL", nil).and_return("https://csidnet.civicrm.org")
    allow(ENV).to receive(:fetch).with("CIVICRM_AUTH_TOKEN", nil).and_return("my-token")
    allow(ENV).to receive(:fetch).with("CSID_ROLE_ASSIGNMENT_ENABLED", "false").and_return("true")
  end

  it "returns empty values without an API request when disabled" do
    allow(ENV).to receive(:fetch).with("CSID_ROLE_ASSIGNMENT_ENABLED", "false").and_return("false")
    expect(described_class).not_to receive(:get)

    expect(service.call.values).to be_empty
  end

  it "checks remotely when forced while disabled" do
    allow(ENV).to receive(:fetch).with("CSID_ROLE_ASSIGNMENT_ENABLED", "false").and_return("false")
    allow(described_class).to receive(:get).and_return(api_response(values: contact_values))

    result = described_class.new("member@example.org", force_remote: true).call

    expect(result.values).to eq(contact_values)
    expect(result.group_id).to eq(15)
  end

  it "returns group 15 when its response contains a contact" do
    stub_api_responses(api_response(values: contact_values))

    result = service.call

    expect(result.to_h).to eq(values: contact_values, group_id: 15, transient_error: false)
    expect(described_class).to have_received(:get).once
    expect(@requested_group_ids).to eq([ 15 ])
  end

  it "checks group 16 after group 15 returns no contacts" do
    stub_api_responses(api_response(values: []), api_response(values: contact_values))

    result = service.call

    expect(result.to_h).to eq(values: contact_values, group_id: 16, transient_error: false)
    expect(@requested_group_ids).to eq([ 15, 16 ])
  end

  it "returns no group when neither response contains a contact" do
    allow(described_class).to receive(:get).and_return(api_response(values: []), api_response(values: []))

    expect(service.call.values).to be_empty
  end

  it "returns empty values when the response omits the values key" do
    response = instance_double(
      "HTTParty::Response",
      success?: true,
      parsed_response: { "count" => 0, "countFetched" => 0 },
      body: ""
    )
    allow(described_class).to receive(:get).and_return(response)

    expect(service.call.values).to be_empty
  end

  it "marks API failures as transient so the worker can retry" do
    failed_response = instance_double("HTTParty::Response", success?: false, code: 503, body: "unavailable")
    allow(described_class).to receive(:get).and_return(failed_response)

    result = service.call

    expect(result.values).to be_empty
    expect(result.transient_error).to be(true)
    expect(described_class).to have_received(:get).once
  end

  def api_response(values:)
    instance_double(
      "HTTParty::Response",
      success?: true,
      parsed_response: { "values" => values, "count" => values.length, "countFetched" => values.length },
      body: ""
    )
  end

  def contact_values
    [
      {
        "id" => 180,
        "email.email" => "member@example.org",
        "user_groups" => [ "Newsletter sign-up", "Committee import" ],
        "user_group_ids" => [ 4, 10 ]
      }
    ]
  end

  def stub_api_responses(*responses)
    @requested_group_ids = []
    allow(described_class).to receive(:get) do |_url, options|
      params = JSON.parse(options.fetch(:query).fetch(:params))
      @requested_group_ids << params.fetch("where").last.last.first
      responses.shift
    end
  end
end
