# frozen_string_literal: true

module PatchworkExtensions
  class Engine < ::Rails::Engine
    isolate_namespace PatchworkExtensions

    # --- Mount routes at "/" ---
    # Prepended (like Gem A) because Mastodon's routes end in a catch-all
    # (`match '*unmatched_route', via: :all, to: 'application#raise_not_found'`);
    # an appended mount would never be reached. Gem A's GEM_SPLIT[COMMUNITY-03]
    # routes block is disabled at cutover, so no duplicate registration remains.
    initializer "patchwork_extensions.load_routes" do |app|
      app.routes.prepend do
        mount PatchworkExtensions::Engine => "/", as: :patchwork_extensions
      end
    end

    # --- Autoload paths for services ---
    # (Rails engines already autoload app/* subdirectories; kept explicit so the
    # intent survives future non-standard directories.)
    config.autoload_paths << root.join("app", "services").to_s

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
