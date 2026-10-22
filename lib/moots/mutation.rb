# frozen_string_literal: true

require_relative "error"
require "digest"
require "json"
require "pathname"

module Moots
  # A single expression replacement, located by byte offset in the original source.
  class Mutation
    attr_reader :original_code, :mutated_code, :line_number, :file_path, :start_offset

    def initialize(original_code:, mutated_code:, line_number:, file_path:, start_offset:)
      @original_code = original_code
      @mutated_code = mutated_code
      @line_number = line_number
      @file_path = file_path
      @start_offset = start_offset
    end

    def relative_path(root: Dir.pwd)
      Pathname.new(File.expand_path(file_path)).relative_path_from(Pathname.new(File.expand_path(root))).to_s
    end

    # Stable across equivalent checkouts; source bytes distinguish each replacement.
    def id(root: Dir.pwd)
      identity = [relative_path(root: root), start_offset, original_code.b.unpack1("H*"), mutated_code.b.unpack1("H*")]
      Digest::SHA256.hexdigest(JSON.generate(identity))[0, 16]
    end

    # Return a changed copy without touching the input or replacing other occurrences.
    def apply(code)
      bytes = code.b
      unless bytes.byteslice(start_offset, original_code.bytesize) == original_code.b
        raise Error, "Source no longer matches mutation at #{file_path}:#{line_number}"
      end

      bytes[start_offset, original_code.bytesize] = mutated_code.b
      bytes.force_encoding(code.encoding)
    end
  end
end
