# frozen_string_literal: true

# MEDIA-01 concern specs. Standalone-capable: the concern is included into a
# minimal stub class, so no Mastodon host is required. The draft-post
# associations stay in Gem A (POST-01) and are not tested here.
require "rails_helper"

RSpec.describe PatchworkExtensions::Concerns::MediaAttachmentConcern, type: :model do
  let(:host_class) do
    klass = Class.new do
      class << self
        def after_save(*); end
      end

      attr_accessor :file_content_type, :description, :status_id, :remote_url, :status

      def initialize(content_type: nil, description: nil)
        @file_content_type = content_type
        @description = description
      end
    end
    klass.include(described_class)
    klass
  end

  it "#is_valid_content_type? returns true for IMAGE_ALLOW_TYPES" do
    instance = host_class.new(content_type: "image/jpeg")
    expect(instance.is_valid_content_type?).to be true
  end

  it "#is_valid_content_type? returns false for non-image types" do
    instance = host_class.new(content_type: "video/mp4")
    expect(instance.is_valid_content_type?).to be false
  end

  it "IMAGE_ALLOW_TYPES includes standard web image formats" do
    host_class.new
    # constant is defined on host class via included block
    expect(host_class::IMAGE_ALLOW_TYPES).to include("image/jpeg", "image/png", "image/gif", "image/webp")
  end

  it "#can_generate_alt? returns false when description already present" do
    instance = host_class.new(content_type: "image/jpeg", description: "existing alt text")
    # check_user_desc? returns false when description is present, so can_generate_alt? should be false
    expect(instance.can_generate_alt?).to be false
  end

  describe "#locally_authored?" do
    it "returns true for locally uploaded media" do
      instance = host_class.new
      instance.remote_url = ""
      expect(instance.locally_authored?).to be true
    end

    it "returns false for remote media not attached to any status" do
      instance = host_class.new
      instance.remote_url = "https://remote.example/media.jpg"
      instance.status_id = nil
      expect(instance.locally_authored?).to be false
    end

    it "returns true for remote media attached to a local status" do
      instance = host_class.new
      instance.remote_url = "https://remote.example/media.jpg"
      instance.status_id = 1
      instance.status = instance_double("Status", local?: true)
      expect(instance.locally_authored?).to be true
    end

    it "returns false for remote media attached to a remote status" do
      instance = host_class.new
      instance.remote_url = "https://remote.example/media.jpg"
      instance.status_id = 1
      instance.status = instance_double("Status", local?: false)
      expect(instance.locally_authored?).to be false
    end

    it "returns false instead of raising when the status has been deleted" do
      instance = host_class.new
      instance.remote_url = "https://remote.example/media.jpg"
      instance.status_id = 1
      instance.status = nil
      expect(instance.locally_authored?).to be false
    end
  end
end
