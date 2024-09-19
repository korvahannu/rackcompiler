# frozen_string_literal: true

require_relative 'rackcompiler/version'
require_relative 'rackcompiler/tokenizer'

module Rackcompiler
  path = ARGV[0]

  Tokenizer.new(path)
end
