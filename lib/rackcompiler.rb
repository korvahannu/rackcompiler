# frozen_string_literal: true

require_relative 'rackcompiler/version'
require_relative 'rackcompiler/tokenizer'
require_relative 'rackcompiler/compilation_engine'

module Rackcompiler
  class Compiler
    def initialize(input_path, output_path: nil)
      @input_path = input_path
      setup_output_directory(input_path, output_path)
    end

    # The input path can either be a single file, or a directory.
    # So handle either case accordingly.
    def compile
      if File.file?(@input_path)
        output_filepath = "#{@output_path}/#{File.basename(@input_path, ".*")}.vm"
        puts "Compiling file '#{@input_path}' to '#{output_filepath}'"
        CompilationEngine.new(@input_path, output_filepath).compile
      else
        files_to_compile = get_files_to_compile(@input_path)
        compile_files(files_to_compile, @output_path, @input_path)
      end
    end

    private

    def compile_files(files, output_path, input_path)
      raise 'Output path not defined, something went horribly wrong!' if output_path.nil?

      files.each do |file|
        output_filepath = "#{output_path}/#{File.basename(file, ".*")}.vm"
        input_filepath = "#{input_path}\\#{file}"

        puts "Compiling file '#{file}' to '#{output_filepath}'"

        CompilationEngine.new(input_filepath, output_filepath).compile
      end
    end

    # Returns an array of input file paths e.g. files that need to be compiled.
    def get_files_to_compile(input_filepath)
      Dir.entries(input_filepath)
         .select { |f| f.end_with?('.jack') }
         .select { |f| File.file?("#{input_filepath}\\#{f}") }
    end

    # Sets up the output directory (e.g. the where to put the files we compile)
    # If no output_path is provided, uses the same directory where the input file(s) are as the output directory.
    def setup_output_directory(input_path, output_path)
      if output_path.nil?
        # Use the input path as the output path
        absolute = File.absolute_path(input_path)
        @output_path = File.directory?(absolute) ? absolute : File.absolute_path(File.dirname(input_path))
      else
        raise 'Output path must be a directory' unless File.directory?(output_path)

        @output_path = File.absolute_path(output_path)
      end
    end
  end

  input_path = ARGV[0]
  raise 'Please provide a filepath' if input_path.nil? || input_path.empty?
  raise 'Invalid filepath: Input file or directory does not exist' unless File.exist?(input_path)

  output_path = ARGV[1]

  Compiler.new(input_path, output_path: output_path).compile
end
