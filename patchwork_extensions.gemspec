# frozen_string_literal: true

require_relative "lib/patchwork_extensions/version"

Gem::Specification.new do |spec|
  spec.name        = "patchwork_extensions"
  spec.version     = PatchworkExtensions::VERSION
  spec.authors     = [ "Patchwork" ]
  spec.email       = [ "akp@binarylab.io" ]

  spec.summary     = "Organization-specific Mastodon extensions (Gem B of the newsmast_mastodon split)."
  spec.description = "Mountable Rails engine carrying custom/proprietary Patchwork features extracted " \
                     "from the newsmast_mastodon gem. First extracted feature: COMMUNITY-03 Starter-Pack Discovery."
  spec.homepage    = "https://github.com/patchwork-hub/patchwork_extensions"
  spec.license     = "AGPL-3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir[
    "app/**/*",
    "config/**/*",
    "lib/**/*",
    "CHANGELOG.md",
    "README.md",
    "LICENSE.txt"
  ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", ">= 7.0", "< 9.0"
  spec.add_dependency "httparty"
  spec.add_dependency "jwt"

  spec.add_development_dependency "rspec", ">= 3.12"
  spec.add_development_dependency "rspec-rails", ">= 6.0"
end
