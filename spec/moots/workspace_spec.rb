# frozen_string_literal: true

RSpec.describe Moots::Workspace do
  def workspace(**options)
    described_class.new(isolation: true, workspace_exclude: [], **options)
  end

  it "copies the current bytes, hidden files and dependencies independently, then removes the copy" do
    in_project do |root|
      source = write_source("lib/math.rb", "# é\r\n1 + 2\xFF".b)
      write_source(".bundle/config", "local configuration")
      write_source("vendor/bundle/dependency.rb", "dependency")
      File.chmod(0o755, source)
      copied = nil
      workspace.open do |copy|
        copied = copy.directory
        expect(copied).not_to eq(root)
        expect(Dir.pwd).to eq(root)
        target = File.join(copied, "lib/math.rb")
        expect(File.binread(target)).to eq(File.binread(source))
        expect(File.stat(target).mode).to eq(File.stat(source).mode)
        expect(File.binread(File.join(copied, ".bundle/config"))).to eq("local configuration")
        expect(File.binread(File.join(copied, "vendor/bundle/dependency.rb"))).to eq("dependency")
        File.binwrite(target, "changed")
        expect(File.binread(source)).to eq("# é\r\n1 + 2\xFF".b)
        expect(copy.original_path(target)).to eq(source)
      end
      expect(File.exist?(copied)).to be(false)
    end
  end

  it "omits nested VCS metadata and matching files or subtrees, including hidden entries" do
    in_project do
      %w[.git/config child/.hg/config child/.svn/config .cache/entry tmp/output lib/drop.rb lib/keep.rb].each do |path|
        write_source(path)
      end
      workspace(workspace_exclude: [".cache", "tmp", "lib/{drop,generated}.rb"]).open do |copy|
        expect(Dir.glob("**/*", File::FNM_DOTMATCH, base: copy.directory).reject do |path|
          File.directory?(File.join(copy.directory, path))
        end)
          .to eq(["lib/keep.rb"])
      end
    end
  end

  it "allows the default exclusions to be replaced, including with an empty list" do
    in_project do
      write_source("tmp/fixture.rb")
      workspace.open { |copy| expect(File.file?(File.join(copy.directory, "tmp/fixture.rb"))).to be(true) }
    end
  end

  it "creates independent workers from the verified snapshot, including baseline artifacts and rebased environment" do
    in_project do |root|
      source = write_source("math.rb", "1 + 2")
      worker_directories = []
      workspace.open do |baseline|
        File.write(source, "later checkout edit")
        FileUtils.mkdir_p(File.join(baseline.directory, "tmp"))
        File.write(File.join(baseline.directory, "tmp/artifact"), "from baseline")
        baseline.with_workers(2) do |copies|
          worker_directories = copies.map(&:directory)
          expect(worker_directories.uniq.size).to eq(2)
          copies.each do |copy|
            expect(File.read(File.join(copy.directory, "math.rb"))).to eq("1 + 2")
            expect(File.read(File.join(copy.directory, "tmp/artifact"))).to eq("from baseline")
            expect(copy.environment("RUBYLIB" => "#{baseline.directory}/lib", "PATH" => "#{root}-outside/bin"))
              .to eq("RUBYLIB" => "#{copy.directory}/lib", "PATH" => "#{root}-outside/bin")
          end
          File.write(File.join(copies.first.directory, "math.rb"), "1 - 2")
          expect(File.read(File.join(copies.last.directory, "math.rb"))).to eq("1 + 2")
          expect(File.read(File.join(baseline.directory, "math.rb"))).to eq("1 + 2")
        end
        expect(worker_directories).to all(satisfy { |path| !File.exist?(path) })
      end
      expect(File.read(source)).to eq("later checkout edit")
    end
  end

  it "cleans up every worker copy when execution fails" do
    in_project do
      directories = []
      workspace.open do |baseline|
        expect do
          baseline.with_workers(2) do |copies|
            directories = copies.map(&:directory)
            raise Interrupt
          end
        end.to raise_error(Interrupt)
        expect(directories).to all(satisfy { |path| !File.exist?(path) })
      end
    end
  end

  it "removes previously prepared workers if a later copy fails" do
    in_project do
      write_source
      workspace.open do |baseline|
        failed_destination = nil
        allow(FileUtils).to receive(:copy_file).and_wrap_original do |original, from, to, preserve|
          if to.include?("/1/")
            failed_destination = to
            raise Errno::ENOSPC
          end
          original.call(from, to, preserve)
        end
        expect { baseline.with_workers(2) { raise "must not run" } }.to raise_error(Errno::ENOSPC)
        expect(File.exist?(File.dirname(failed_destination, 2))).to be(false)
        expect(File.read(File.join(baseline.directory, "example.rb"))).to eq("a + b")
      end
    end
  end

  it "maps glob results and literal argument paths while preserving strings and external paths" do
    in_project do |root|
      first = write_source("lib/a.rb")
      write_source("lib/b.rb")
      workspace.open do |copy|
        expected = %w[a.rb b.rb].map { |name| File.join(copy.directory, "lib", name) }
        expect(copy.files(["lib/*.rb", first, "missing.rb"])).to eq(expected)
        expect(copy.command([root, first, "lib/a.rb", "--option", "#{root}-sibling/a.rb"]))
          .to eq([copy.directory, expected.first, "lib/a.rb", "--option", "#{root}-sibling/a.rb"])
        expect(copy.command("ruby #{first}")).to eq("ruby #{first}")
        expect { copy.files(["../*.rb"]) }.to raise_error(Moots::Error, /escapes the project/)
        expect { copy.files(["#{root}-sibling/*.rb"]) }.to raise_error(Moots::Error, /escapes the project/)
      end
    end
  end

  it "rebases inherited Bundler and Ruby search paths without altering the parent environment" do
    in_project do |root|
      values = {
        "BUNDLE_GEMFILE" => "#{root}/Gemfile", "BUNDLE_APP_CONFIG" => "#{root}/.bundle",
        "BUNDLE_BIN_PATH" => "#{root}/vendor/bundle/bin/bundle", "BUNDLE_PATH" => "#{root}/vendor/bundle",
        "GEM_HOME" => "#{root}/gems", "GEM_PATH" => ["#{root}/gems", "#{root}-other/gems"].join(File::PATH_SEPARATOR),
        "RUBYLIB" => ["#{root}/lib", "", "relative"].join(File::PATH_SEPARATOR), "PATH" => "#{root}/bin",
        "BUNDLER_ORIG_BUNDLE_GEMFILE" => "#{root}/Gemfile"
      }
      allow(ENV).to receive(:key?).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      values.each do |key, value|
        allow(ENV).to receive(:key?).with(key).and_return(true)
        allow(ENV).to receive(:fetch).with(key).and_return(value)
      end
      allow(ENV).to receive(:key?).with("BUNDLER_ORIG_GEM_HOME").and_return(false)
      before = ENV.to_h
      workspace.open do |copy|
        mapped = copy.environment
        values.each do |key, value|
          expect(mapped.fetch(key)).to eq(value.gsub("#{root}/", "#{copy.directory}/"))
        end
        expect(mapped).not_to have_key("BUNDLER_ORIG_GEM_HOME")
        expect(ENV.to_h).to eq(before)
      end
    end
  end

  it "rejects glob alternatives that expand beyond the working copy" do
    in_project do
      Dir.mktmpdir("moots-outside-") do |outside|
        File.write(File.join(outside, "untouched.rb"), "1 + 2")
        workspace.open do |copy|
          expect { copy.files(["{../#{File.basename(outside)},lib}/*.rb"]) }
            .to raise_error(Moots::Error, /Selected source escapes/)
        end
        expect(File.read(File.join(outside, "untouched.rb"))).to eq("1 + 2")
      end
    end
  end

  it "rejects links introduced into the copy by a baseline command", unless: Gem.win_platform? do
    in_project do |root|
      source = write_source
      workspace.open do |copy|
        File.symlink(source, File.join(copy.directory, "introduced.rb"))
        expect { copy.files(["introduced.rb"]) }.to raise_error(Moots::Error, /Selected source escapes/)
      end
      expect(File.read(File.join(root, "example.rb"))).to eq("a + b")
    end
  end

  it "rebases existing project paths reached through an external directory alias", unless: Gem.win_platform? do
    in_project do |root|
      write_source("Gemfile", "source 'https://rubygems.org'")
      Dir.mktmpdir("moots-alias-") do |outside|
        link = File.join(outside, "linked-project")
        File.symlink(root, link)
        workspace.open do |copy|
          expect(copy.command([File.join(link, "Gemfile")])).to eq([File.join(copy.directory, "Gemfile")])
        end
      end
    end
  end

  [RuntimeError, Interrupt].each do |error|
    it "cleans up after #{error}" do
      in_project do
        copied = nil
        expect do
          workspace.open do |copy|
            copied = copy.directory
            raise error, "stop"
          end
        end.to raise_error(error, "stop")
        expect(File.exist?(copied)).to be(false)
      end
    end
  end

  it "cleans up partial copies and propagates I/O errors before executing tests" do
    in_project do
      source = write_source
      destination = nil
      allow(FileUtils).to receive(:copy_file).with(source, anything, true) do |_from, to|
        destination = to
        File.write(to, "partial")
        raise Errno::ENOSPC
      end
      expect { workspace.open { raise "must not run" } }.to raise_error(Errno::ENOSPC)
      expect(File.exist?(File.dirname(destination))).to be(false)
      expect(File.read(source)).to eq("a + b")
    end
  end

  it "rejects a temporary directory inside the project before recursively copying itself" do
    in_project do |root|
      allow(Dir).to receive(:tmpdir).and_return(root)
      expect { workspace.open { raise "must not run" } }.to raise_error(Moots::Error, /Temporary directory/)
    end
  end

  it "supports explicit in-place operation without copying or restricting existing source patterns" do
    in_project do |root|
      path = write_source
      expect(Dir).not_to receive(:mktmpdir)
      workspace(isolation: false).open do |copy|
        expect(copy.directory).to eq(root)
        expect(copy.files(["../#{File.basename(root)}/*.rb"])).to eq([path])
        expect(copy.command([path])).to eq([path])
        expect(copy.original_path(path)).to eq(path)
      end
    end
  end

  it "rejects resolved path aliases such as Windows directory junctions" do
    in_project do |root|
      path = write_source
      allow(File).to receive(:realpath).and_call_original
      allow(File).to receive(:realpath).with(path).and_return("#{root}/different")
      expect { workspace.open { raise "must not run" } }.to raise_error(Moots::Error, /Cannot isolate linked path/)
    end
  end

  it "rejects a real Windows directory junction without changing its target", if: Gem.win_platform? do
    in_project do
      target = File.dirname(write_source("target/example.rb"))
      link = File.expand_path("junction")
      expect(system("cmd", "/c", "mklink", "/J", link.tr("/", "\\"), target.tr("/", "\\"),
                    out: File::NULL, err: File::NULL)).to be(true)
      begin
        expect { workspace.open { raise "must not run" } }.to raise_error(Moots::Error, /linked path junction/)
        expect(File.read(File.join(target, "example.rb"))).to eq("a + b")
      ensure
        Dir.rmdir(link)
      end
    end
  end

  it "rejects special files instead of hanging while copying them" do
    in_project do
      path = write_source
      stat = instance_double(File::Stat, symlink?: false, directory?: false, file?: false)
      allow(File).to receive(:lstat).and_call_original
      allow(File).to receive(:lstat).with(path).and_return(stat)
      expect { workspace.open { raise "must not run" } }.to raise_error(Moots::Error, /Cannot isolate special file/)
    end
  end

  it "rejects internal, external and broken symlinks but permits excluding them", unless: Gem.win_platform? do
    in_project do |root|
      source = write_source
      [source, File.dirname(root), "missing"].each do |target|
        File.symlink(target, "linked")
        expect { workspace.open { raise "must not run" } }.to raise_error(Moots::Error, /linked path linked/)
        workspace(workspace_exclude: ["linked"]).open do |copy|
          expect(File.exist?(File.join(copy.directory, "linked"))).to be(false)
        end
        File.unlink("linked")
      end
    end
  end
end
