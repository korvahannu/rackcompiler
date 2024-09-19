# frozen_string_literal: true

require_relative 'lib/rackcompiler/version'

Gem::Specification.new do |spec|
  spec.name = 'rackcompiler'
  spec.version = Rackcompiler::VERSION
  spec.authors = ['Hannu Korvala']
  spec.email = ['hannu.s.korvala@gmail.com']

  spec.summary = 'Jack compiler implemented with Ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
end
