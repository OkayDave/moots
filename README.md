# Moots

Moots is a simple, open-source mutation testing tool for Ruby, inspired by the mutant gem but with a more focused scope. It helps you improve your test suite by introducing small changes (mutations) to your code and checking if your tests can detect these changes.

## What is Mutation Testing?

Mutation testing is a method of evaluating the quality of your test suite. It works by:

1. Making small changes (mutations) to your code
2. Running your test suite against the mutated code
3. Checking if your tests can detect these changes

If your tests fail when the code is mutated, that's good! It means your tests are catching potential bugs. If your tests pass with mutated code, it suggests your test coverage might need improvement.

## Why Use Moots?

While there are other mutation testing tools available for Ruby (like mutant), Moots aims to be:

- **Simple**: Focused on core mutation testing features
- **Fast**: Optimized for quick feedback cycles
- **Open Source**: Fully MIT licensed and community-driven
- **Rails-friendly**: Designed with Ruby on Rails applications in mind

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'moots'
```

And then execute:

```bash
bundle install
```

## Basic Usage

To run mutation testing on your codebase:

```bash
bundle exec moots
```

By default, Moots will:
1. Analyse your test suite
2. Generate mutations for your code
3. Run your tests against each mutation
4. Report which mutations were caught and which weren't

## Configuration

Create a `.moots.yml` file in your project root to configure Moots:

```yaml
# Example configuration
include:
  - app/**/*.rb
  - lib/**/*.rb
exclude:
  - app/models/concerns/**/*.rb
test_command: bundle exec rspec
```

## How It Works: A Deep Dive

Let's break down exactly how Moots performs mutation testing, step by step:

### 1. Finding Files to Test

Moots starts by scanning your codebase for Ruby files based on your configuration:
- It uses Ruby's `Dir[]` glob pattern matching to find files matching your `include` patterns
- It excludes any files matching your `exclude` patterns
- It checks each file is readable before processing

### 2. Parsing and Understanding Your Code

For each Ruby file, Moots:
1. Reads the file content
2. Uses the [parser](https://github.com/whitequark/parser) gem to convert your Ruby code into an Abstract Syntax Tree (AST)
   - An AST is a tree representation of your code's structure
   - This lets Moots understand your code's meaning, not just its text

### 3. Generating Mutations

Moots walks through the AST looking for code it can mutate. Currently, it handles:

a) Arithmetic Operators:
   - Changes `+` to `-`
   - Changes `-` to `+`
   - Changes `*` to `/`
   - Changes `/` to `*`

b) Boolean Operators:
   - Changes `&&` to `||`
   - Changes `||` to `&&`

For example, this code:
```ruby
def add(a, b)
  a + b
end
```

Becomes:
```ruby
def add(a, b)
  a - b  # The + operator was mutated to -
end
```

### 4. Testing Each Mutation

For each mutation, Moots:
1. Temporarily modifies your source file with the mutation
2. Runs your test command (e.g., `bundle exec rspec`)
3. Captures the test output and result
4. Restores your original code
5. Records whether the mutation was "killed" (tests failed) or "survived" (tests passed)

### 5. Safety Measures

Moots includes several safety features:
- Always restores your original code, even if tests fail
- Handles file read/write errors gracefully
- Skips unreadable or invalid files
- Uses Ruby's `Open3.capture3` to safely run test commands

### Further Reading

- [Abstract Syntax Trees (AST)](https://en.wikipedia.org/wiki/Abstract_syntax_tree)
- [Ruby Parser Documentation](https://github.com/whitequark/parser)
- [Mutation Testing Paper](https://www.cs.cmu.edu/~agroce/testing21.pdf) by Alex Groce et al.
- [Why Mutation Testing?](https://testing.googleblog.com/2021/04/mutation-testing.html) - Google Testing Blog

## Code Architecture

Moots is built with a clean, modular architecture. Here's how the different components work together:

### Core Classes

1. **`Moots` (main.rb)**
   - The entry point of the application
   - Orchestrates the mutation testing process
   - Handles configuration loading and file processing
   - Manages the overall mutation testing workflow

2. **`MutationGenerator` (mutation_generator.rb)**
   - Responsible for analyzing Ruby code and generating mutations
   - Uses the parser gem to build ASTs
   - Walks through the AST to find mutation points
   - Generates different types of mutations (arithmetic, boolean)
   - Handles file path inclusion/exclusion logic

3. **`TestRunner` (test_runner.rb)**
   - Executes test commands against mutated code
   - Captures and processes test output
   - Handles test command execution safely
   - Manages stdout/stderr capture
   - Determines if mutations were killed or survived

4. **`Configuration` (configuration.rb)**
   - Manages loading and validation of `.moots.yml`
   - Handles default configuration values
   - Validates include/exclude patterns
   - Manages test command configuration

### Supporting Classes

1. **`Mutation` (mutation.rb)**
   - Represents a single code mutation
   - Stores mutation location and type
   - Handles mutation application and reversion
   - Tracks mutation status (killed/survived)

2. **`FileHandler` (file_handler.rb)**
   - Manages file operations
   - Handles file reading and writing
   - Ensures safe file modifications
   - Manages file backup and restoration

### How They Work Together

1. `Moots` loads configuration and starts the process
2. `MutationGenerator` analyzes files and creates mutations
3. For each mutation:
   - `FileHandler` backs up the original file
   - `Mutation` applies the change
   - `TestRunner` runs the tests
   - `FileHandler` restores the original file
4. Results are collected and reported

This modular design makes it easy to:
- Add new mutation types
- Support different test runners
- Extend configuration options
- Handle different file types
- Add new features

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/OkayDave/moots. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/OkayDave/moots/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Moots project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/OkayDave/moots/blob/master/CODE_OF_CONDUCT.md).
