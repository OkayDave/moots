# frozen_string_literal: true

RSpec.describe ProjectHelpers do
  it "yields the resolved working directory when temporary projects use a directory alias", unless: Gem.win_platform? do
    Dir.mktmpdir("moots-path-alias-") do |parent|
      real_directory = File.join(parent, "project")
      alias_directory = File.join(parent, "alias")
      FileUtils.mkdir_p(real_directory)
      File.symlink(real_directory, alias_directory)
      allow(Dir).to receive(:mktmpdir).with("moots-spec-").and_yield(alias_directory)

      in_project do |directory|
        expect(directory).to eq(Dir.pwd)
        expect(directory).to eq(File.realpath(real_directory))
        path = write_source("lib/math.rb", "a + b")
        expect(path).to eq(File.join(directory, "lib/math.rb"))
      end
    end
  end
end
