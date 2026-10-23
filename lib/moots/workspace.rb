# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "pathname"
require_relative "error"
require_relative "environment"

module Moots
  # A disposable snapshot of the current project, with paths mapped back for reports.
  class Workspace
    METADATA = %w[.git .hg .svn].freeze

    attr_reader :directory

    def initialize(isolation:, workspace_exclude:, root: Dir.pwd)
      @root = File.realpath(root)
      @directory = @root
      @isolation = isolation
      @exclude = workspace_exclude
    end

    def open
      return yield self unless @isolation

      if inside?(File.realpath(Dir.tmpdir))
        raise Error, "Temporary directory must be outside the project for isolated runs"
      end

      Dir.mktmpdir("moots-workspace-") do |temporary|
        @directory = File.realpath(temporary)
        copy_directory(@root, @directory)
        yield self
      end
    end

    def files(patterns)
      patterns.flat_map do |pattern|
        absolute = File.expand_path(pattern, @root)
        raise Error, "Source pattern escapes the project: #{pattern}" if @isolation && !inside?(absolute)

        Dir.glob(rebase(absolute)).map { |path| selected_path(path) }
      end.uniq.sort
    end

    def with_workers(count)
      Dir.mktmpdir("moots-workers-") do |temporary|
        directory = File.realpath(temporary)
        workers = Array.new(count) do |index|
          self.class.new(isolation: true, workspace_exclude: [], root: @directory)
              .copy_to(File.join(directory, index.to_s))
        end
        yield workers
      end
    end

    def original_path(path)
      File.expand_path(Pathname.new(path).relative_path_from(Pathname.new(@directory)).to_s, @root)
    end

    def command(value)
      return value unless value.is_a?(Array)

      value.map { |argument| rebase(argument) }
    end

    def environment(source = ENV)
      Environment.rebase(source) { |path| rebase(path) }
    end

    protected

    def copy_to(destination)
      @directory = destination
      Dir.mkdir(destination)
      copy_directory(@root, destination)
      self
    end

    private

    def inside?(path, root = @root)
      path == root || path.start_with?("#{root}/")
    end

    def selected_path(path)
      absolute = File.expand_path(path)
      if @isolation && (!inside?(absolute, @directory) || File.realpath(absolute) != absolute)
        raise Error, "Selected source escapes or links outside the working copy: #{path}"
      end

      absolute
    end

    def rebase(path)
      return path unless Pathname.new(path).absolute?

      absolute = File.exist?(path) ? File.realpath(path) : File.expand_path(path)
      return path unless inside?(absolute)

      File.expand_path(Pathname.new(absolute).relative_path_from(Pathname.new(@root)).to_s, @directory)
    end

    def excluded?(relative, name)
      METADATA.include?(name) || @exclude.any? do |pattern|
        File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB)
      end
    end

    def copy_directory(source, destination)
      Dir.children(source).each do |name|
        path = File.join(source, name)
        relative = Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
        next if excluded?(relative, name)

        stat = File.lstat(path)
        if stat.symlink? || File.realpath(path) != path
          raise Error,
                "Cannot isolate linked path #{relative}; exclude it with workspace_exclude or use isolation: false"
        end

        copy_entry(path, File.join(destination, name), stat)
      end
    end

    def copy_entry(source, destination, stat)
      if stat.directory?
        Dir.mkdir(destination)
        copy_directory(source, destination)
      elsif stat.file?
        FileUtils.copy_file(source, destination, true)
      else
        raise Error, "Cannot isolate special file #{source}; exclude it with workspace_exclude"
      end
    end
  end
end
