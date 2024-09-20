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

      files.each do |file|
        output_filepath = "#{@output_path}/#{File.basename(file, '.*')}.vm"
        puts "Compiling file '#{file}' to '#{output_filepath}'"
        get_tokenizer(file, is_directory)
      end
    end

    def get_tokenizer(file, is_directory)
      if is_directory
        Tokenizer.new("#{@filepath}\\#{file}")
      else
        Tokenizer.new(file)
      end
    end

    def get_files_to_compile(filepath)
      Dir.entries(filepath)
         .select { |f| f.end_with?('.jack') }
         .select { |f| File.file?("#{@filepath}\\#{f}") }
    end

    def get_file_basename(filepath)
      File.basename(filepath, '.*')
    end

    def setup_output_path(filepath, output_path)
      if output_path.nil?
        derive_output_file_name(filepath)
      else
        raise 'Output path must be a directory' unless File.directory?(output_path)

        @output_path = File.absolute_path(output_path)
      end

      puts @output_path
    end

    def derive_output_file_name(filepath)
      absolute = File.absolute_path(filepath)
      @output_path = File.directory?(absolute) ? absolute : File.absolute_path(File.dirname(filepath))
    end
  end

  filepath = ARGV[0]
  raise 'Please provide a filepath' if filepath.nil? || filepath.empty?
  raise 'Invalid filepath: Input file or directory does not exist' unless File.exist?(filepath)

  output_path = ARGV[1]

  Compiler.new(filepath, output_path: output_path).compile
end
