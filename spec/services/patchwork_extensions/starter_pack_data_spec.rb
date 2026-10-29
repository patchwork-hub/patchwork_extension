# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../app/services/patchwork_extensions/starter_pack_data"

RSpec.describe PatchworkExtensions::StarterPackData do
  # Minimal Redis stand-in with the get/set(ex:) interface the loader uses.
  class FakeRedis
    attr_reader :writes

    def initialize
      @store = {}
      @writes = []
    end

    def get(key)
      @store[key]
    end

    def set(key, value, ex: nil)
      @writes << { key: key, ex: ex }
      @store[key] = value
    end
  end

  let(:redis) { FakeRedis.new }
  let(:data_root) { Pathname.new(Dir.mktmpdir("starter-packs")) }
  let(:loader) { described_class.new(redis: redis, data_root: data_root) }
  let(:relative_path) { "twt/starter_pack_list.json" }
  let(:payload) { [ { "id" => "1", "title" => "Fun, Funny and Fantastic" } ] }

  before do
    FileUtils.mkdir_p(data_root.join("twt"))
  end

  after do
    FileUtils.remove_entry(data_root)
  end

  def write_fixture(contents)
    File.write(data_root.join(relative_path), contents)
  end

  it "parses and returns JSON data from the data root" do
    write_fixture(payload.to_json)

    expect(loader.load(relative_path, namespace: "twt")).to eq(payload)
  end

  it "returns an empty array when the file is missing" do
    expect(loader.load(relative_path, namespace: "twt")).to eq([])
  end

  it "caches parsed data in Redis with a 24-hour expiry" do
    write_fixture(payload.to_json)
    loader.load(relative_path, namespace: "twt")

    expect(redis.writes.length).to eq(1)
    expect(redis.writes.first[:ex]).to eq(24.hours.to_i)
  end

  it "serves cached data without re-reading when the mtime matches" do
    write_fixture(payload.to_json)
    loader.load(relative_path, namespace: "twt")

    # Corrupt the file contents without changing mtime; cache should win.
    cached_result = loader.load(relative_path, namespace: "twt")
    expect(cached_result).to eq(payload)
  end

  it "refreshes the cache when the file mtime changes" do
    write_fixture(payload.to_json)
    loader.load(relative_path, namespace: "twt")

    updated = [ { "id" => "2", "title" => "Updated Pack" } ]
    write_fixture(updated.to_json)
    future = Time.now + 60
    FileUtils.touch(data_root.join(relative_path), mtime: future)

    expect(loader.load(relative_path, namespace: "twt")).to eq(updated)
    expect(redis.writes.length).to eq(2)
  end

  it "derives the legacy-compatible cache key" do
    expect(described_class.cache_key(namespace: "twt", relative_path: relative_path))
      .to eq("accounts:starter_pack_twt_twt_starter_pack_list")
  end
end
