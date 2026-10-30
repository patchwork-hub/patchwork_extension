# frozen_string_literal: true

# MEDIA-01 service specs. Standalone-capable: the AltText.ai client only needs
# HTTParty and the response wrappers, both of which load without the host.
require "rails_helper"

RSpec.describe PatchworkExtensions::AltTextAiApiService, type: :service do
  it "#get_account returns account info (HTTParty stub)" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALT_TEXT_URL").and_return("https://alt.example/")
    allow(ENV).to receive(:[]).with("ALT_TEXT_SECRET").and_return("secret")

    response = instance_double("HTTPartyResponse", body: { account: { id: 1 } }.to_json)
    allow(HTTParty).to receive(:get).and_return(response)

    stub_const("PatchworkExtensions::AlttextGetAccount", Class.new do
      attr_reader :payload
      def initialize(payload)
        @payload = payload
      end
    end)

    result = described_class.new.get_account

    expect(HTTParty).to have_received(:get).with(
      "https://alt.example/account",
      headers: hash_including("X-API-Key" => "secret")
    )
    expect(result.payload).to eq("account" => { "id" => 1 })
  end

  it "#create_image posts image and returns alt text (HTTParty stub)" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALT_TEXT_URL").and_return("https://alt.example/")
    allow(ENV).to receive(:[]).with("ALT_TEXT_SECRET").and_return("secret")

    response = instance_double("HTTPartyResponse", body: { alt_text: "a red kite" }.to_json)
    allow(HTTParty).to receive(:post).and_return(response)

    stub_const("PatchworkExtensions::AlttextCreateImage", Class.new do
      attr_reader :payload
      def initialize(payload)
        @payload = payload
      end
    end)

    payload = { image_url: "https://img.example/kite.jpg" }
    result = described_class.new(payload: payload).create_image

    expect(HTTParty).to have_received(:post).with(
      "https://alt.example/images",
      body: payload.to_json,
      headers: hash_including("X-API-Key" => "secret")
    )
    expect(result.payload).to eq("alt_text" => "a red kite")
  end
end
