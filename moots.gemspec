# frozen_string_literal: true

require_relative "lib/moots/version"

Gem::Specification.new do |spec|
  spec.name = "moots"
  spec.version = Moots::VERSION
  spec.authors = ["Dave Russell"]
  spec.email = ["dave.kerr@gmail.com"]

  spec.summary = "Moots is a simple tool to provide mutation testing for Ruby"
  spec.homepage = "https://github.com/OkayDave/moots"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/OkayDave/moots"
  spec.metadata["changelog_uri"] = "https://github.com/OkayDave/moots/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "exe/*", "sig/**/*.rbs", "*.md", "LICENSE.txt"] }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", "~> 1.9"
end
