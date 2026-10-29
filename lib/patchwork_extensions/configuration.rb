# frozen_string_literal: true

require "pathname"

module PatchworkExtensions
  class Configuration
    # Directory containing the starter-pack JSON datasets. Defaults to the
    # gem's packaged config/data; override in the host for custom datasets
    # or in specs for deterministic fixtures.
    attr_accessor :starter_pack_data_root

    def initialize
      @starter_pack_data_root = nil
    end

    def resolved_starter_pack_data_root
      Pathname.new(@starter_pack_data_root || Engine.root.join("config", "data"))
    end
  end
end
