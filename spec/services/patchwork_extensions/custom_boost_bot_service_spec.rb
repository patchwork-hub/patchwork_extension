# frozen_string_literal: true

require "rails_helper"

RSpec.describe PatchworkExtensions::CustomBoostBotService, type: :service do
  it "sends a custom status boost request" do
    account = instance_double("Account", username: "alice", domain: nil)
    status = instance_double("Status", id: 55, account: account)

    status_class = Class.new do
      def self.find_by(*); end
    end
    stub_const("Status", status_class)
    allow(Status).to receive(:find_by).with(id: 55).and_return(status)

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CHANNEL_CLIENT_ID", nil).and_return("client-id")
    allow(ENV).to receive(:fetch).with("CHANNEL_CLIENT_SECRET", nil).and_return("client-secret")
    allow(ENV).to receive(:fetch).with("CHANNEL_INSTANCE_URL", nil).and_return("https://channel.example")

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LOCAL_DOMAIN").and_return("local.example")

    response = instance_double("HTTPartyResponse")
    allow(HTTParty).to receive(:post).and_return(response)

    result = described_class.new(55, "channel").call

    expect(HTTParty).to have_received(:post).with(
      "https://channel.example/api/v1/custom_statuses/add_custom_boost_bot_status",
      body: kind_of(String),
      headers: { "Content-Type" => "application/json" }
    )
    expect(result).to eq(response)
  end
end
