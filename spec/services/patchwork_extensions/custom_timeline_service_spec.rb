# frozen_string_literal: true

require "rails_helper"

RSpec.describe PatchworkExtensions::CustomTimelineService do
  it "adds public statuses to the mix timeline Redis set" do
    redis = instance_double("Redis")
    allow(redis).to receive(:zadd)
    allow(redis).to receive(:zremrangebyrank)

    service = described_class.new
    service.define_singleton_method(:redis) { redis }
    service.add_custom_public_status(100)

    expect(redis).to have_received(:zadd).with("feed:mix_channel_local_timeline", 100, 100)
  end

  it "removes statuses from the mix timeline Redis set" do
    redis = instance_double("Redis")
    allow(redis).to receive(:zrem)

    service = described_class.new
    service.define_singleton_method(:redis) { redis }
    service.remove_custom_public_status(100)

    expect(redis).to have_received(:zrem).with("feed:mix_channel_local_timeline", 100)
  end
end
