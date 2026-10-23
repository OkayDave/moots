# frozen_string_literal: true

module Moots
  # Relocate known Bundler and Ruby path variables without editing the parent environment.
  module Environment
    PATH_VARIABLES = %w[BUNDLE_GEMFILE BUNDLE_APP_CONFIG BUNDLE_BIN_PATH BUNDLE_PATH GEM_HOME].freeze
    PATH_LISTS = %w[GEM_PATH RUBYLIB PATH].freeze

    def self.rebase(source, &mapper)
      (PATH_VARIABLES + PATH_LISTS).each_with_object({}) do |name, overrides|
        [name, "BUNDLER_ORIG_#{name}"].each do |key|
          next unless source.key?(key)

          overrides[key] = if PATH_LISTS.include?(name)
                             source.fetch(key).split(File::PATH_SEPARATOR, -1).map(&mapper).join(File::PATH_SEPARATOR)
                           else
                             mapper.call(source.fetch(key))
                           end
        end
      end
    end
  end
end
