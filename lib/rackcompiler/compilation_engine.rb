# frozen_string_literal: true

class CompilationEngine
  def initialize(input_file, _output_file)
    @tokenizer = Tokenizer.new(input_file)
    raise 'Empty tokenizer ' unless @tokenizer.has_more_tokens?
  end

  def compile; end

  private

  def compile_class; end

  def compile_class_var_dec; end

  def compile_subroutine; end

  def compile_parameter_list; end

  def compile_subroutine_body; end

  def compile_var_dec; end

  def compile_statements; end

  def compile_let; end

  def compile_if; end

  def compile_while; end

  def compile_do; end

  def compile_return; end

  def compile_expression; end

  def compile_term; end

  def compile_expression_list; end
end
