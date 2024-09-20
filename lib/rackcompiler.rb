# frozen_string_literal: true

require_relative 'rackcompiler/version'
require_relative 'rackcompiler/tokenizer'

module Rackcompiler
  class Compiler
    def initialize(filepath, output_path: nil)
      @filepath = filepath
      setup_output_path(filepath, output_path)
    end

    def compile
      if File.file?(@filepath)
        compile_file(@filepath)
      else
        compile_files get_files_to_compile(@filepath)
      end
    end

    private

    def compile_file(file)
      compile_files([file], is_directory: false)
    end

    def compile_files(files, is_directory: true)
      raise 'Output path not defined, something went horribly wrong!' if @output_path.nil?

      File.open(@output_path, 'w') do |output_file|
        files.each do |file|
          get_tokenizer(file, is_directory)
        end
      end
    end

    def get_tokenizer(file, is_directory)
      if is_directory
        Tokenizer.new("#{@filepath}#{file}")
      else
        Tokenizer.new(file)
      end
    end

    def get_files_to_compile(filepath)
      Dir.entries(filepath)
         .select { |f| f.end_with?(".vm") }
         .select { |f| File.file?("#{@filepath}#{f}") }
    end

    def get_file_basename(filepath)
      File.basename(filepath, '.*')
    end

    def setup_output_path(filepath, output_path)
      if @output_path.nil?
        derive_output_file_name(filepath)
      else
        @output_path = output_path
      end
    end

    def derive_output_file_name(filepath)
      basename = get_file_basename(filepath)
      @output_path = File.file?(filepath) ? "#{basename}.asm" : "#{basename.capitalize}.asm"
      puts @output_path
    end
  end

  filepath = ARGV[0]
  raise 'Please provide a filepath' if filepath.nil? || filepath.empty?
  raise 'Invalid filepath: Input file or directory does not exist' unless File.exist?(filepath)

  Compiler.new(filepath).compile
end
