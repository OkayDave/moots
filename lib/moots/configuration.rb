# frozen_string_literal: true

require "yaml"
require_relative "error"

module Moots
  # Load safe YAML and validate the options shared by the CLI and Ruby API.
  class Configuration
    DEFAULTS = {
      include: ["app/**/*.rb", "lib/**/*.rb"].freeze,
      exclude: [].freeze,
      test_command: "bundle exec rspec",
      timeout: 60
    }.freeze

    def self.load(path)
      new(YAML.safe_load_file(path)).to_h
    rescue Psych::Exception, SystemCallError => e
      raise Error, "Cannot load configuration #{path}: #{e.message}"
    end

    def initialize(options = {})
      raise Error, "Configuration must be a mapping" unless options.is_a?(Hash)

      normalized = options.transform_keys(&:to_s)
      unknown = normalized.keys - DEFAULTS.keys.map(&:to_s)
      raise Error, "Unknown configuration keys: #{unknown.join(", ")}" unless unknown.empty?

      @options = DEFAULTS.merge(normalized.transform_keys(&:to_sym))
      validate_patterns(:include)
      validate_patterns(:exclude)
      validate_command
      timeout = @options[:timeout]
      return if timeout.is_a?(Numeric) && timeout.real? && timeout.finite? && timeout.positive?

      raise Error, "timeout must be a positive finite number of seconds"
    end

    def to_h
      @options.dup
    end

    private

    def validate_patterns(key)
      patterns = @options[key]
      return if patterns.is_a?(Array) && patterns.all? { |pattern| valid_string?(pattern) }

      raise Error, "#{key} must be an array of non-empty glob strings"
    end

    def validate_command
      command = @options[:test_command]
      return if valid_string?(command)
      return if command.is_a?(Array) && !command.empty? && command.all? { |part| valid_string?(part) }

      raise Error, "test_command must be a non-empty string or argument array"
    end

    def valid_string?(value)
      value.is_a?(String) && !value.strip.empty? && !value.include?("\0")
    end
  end
end
