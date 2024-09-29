# frozen_string_literal: true

require_relative 'vm_writer'
require_relative 'symbol_table'

class ProcessingError < Exception
end

class CompilationEngine
  INDENT_SPACES = 2

  def initialize(input_filepath, output_filepath)
    @input_filepath = input_filepath
    @output_filepath = output_filepath
    @current_depth = 0
    @code = String.new

    @writer = VMWriter.new
    @class_symbol_table = SymbolTable.new
    @subroutine_symbol_table = SymbolTable.new

    @tokenizer = Tokenizer.new(@input_filepath)
    raise 'Empty tokenizer ' unless @tokenizer.has_more_tokens?
  end

  def compile
    compile_class
    @code.strip!

    puts @writer.code.strip

    @tokenizer.reset
  end

  private

  def compile_class
    output('<class>')
    ascend
    process(token: 'class', token_type: 'keyword')
    process(token_type: 'identifier')
    process(token: '{', token_type: 'symbol')
    compile_class_var_dec while %w[static field].include?(@tokenizer.peek_token)
    compile_subroutine while %w[constructor function method].include?(@tokenizer.peek_token)
    process(token: '}', token_type: 'symbol')
    descend
    output('</class>')
  end

  def compile_class_var_dec
    expect(tokens: %w[static field], token_type: 'keyword')
    kind = advance_and_get.to_sym
    expect_type
    type = advance_and_get
    expect(token_type: 'identifier')
    name = advance_and_get
    @class_symbol_table.define(name, type, kind)
    while @tokenizer.peek_token == ','
      process(token: ',', token_type: 'symbol')
      name = advance_and_get
      @class_symbol_table.define(name, type, kind)
    end
    process(token: ';', token_type: 'symbol')
  end

  def compile_subroutine
    @subroutine_symbol_table = @subroutine_symbol_table.append
    process(tokens: %w[constructor function method], token_type: 'keyword')
    process_or -> { process_type }, -> { process(token: 'void', token_type: 'keyword') }
    function_name = advance_and_get
    process(token: '(', token_type: 'symbol')
    parameter_count = compile_parameter_list
    process(token: ')', token_type: 'symbol')
    @writer.write_function(function_name, parameter_count)
    @writer.indent
    compile_subroutine_body
    @writer.undent
    @subroutine_symbol_table = @subroutine_symbol_table.reject
  end

  def compile_parameter_list
    parameter_count = 0
    while @tokenizer.peek_token != ')'
      expect_type
      type = advance_and_get
      expect(token_type: 'identifier')
      name = advance_and_get
      @subroutine_symbol_table.define(name, type, :arg)
      parameter_count += 1
      process(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end
    parameter_count
  end

  def compile_subroutine_body
    process(token: '{', token_type: 'symbol')
    compile_var_dec while @tokenizer.peek_token == 'var'
    compile_statements
    process(token: '}', token_type: 'symbol')
  end

  def compile_var_dec
    process(token: 'var', token_type: 'keyword')
    expect_type
    type = advance_and_get

    while @tokenizer.peek_token != ';'
      identifier = advance_and_get
      @subroutine_symbol_table.define(identifier, type, :var)
      process(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end

    process(token: ';', token_type: 'symbol')
  end

  def compile_statements
    peeked_token = @tokenizer.peek_token
    while %w[let if while do return].include?(peeked_token)
      compile_let if peeked_token == 'let'
      compile_if if peeked_token == 'if'
      compile_while if peeked_token == 'while'
      compile_do if peeked_token == 'do'
      compile_return if peeked_token == 'return'
      peeked_token = @tokenizer.peek_token
    end
  end

  def compile_let #TODO
    output('<letStatement>')
    ascend
    process(token: 'let', token_type: 'keyword')
    process(token_type: 'identifier')
    if @tokenizer.peek_token == '['
      process(token: '[', token_type: 'symbol')
      compile_expression
      process(token: ']', token_type: 'symbol')
    end
    process(token: '=', token_type: 'symbol')
    compile_expression
    process(token: ';', token_type: 'symbol')
    descend
    output('</letStatement>')
  end

  def compile_if #TODO
    output('<ifStatement>')
    ascend
    process(token: 'if', token_type: 'keyword')
    process(token: '(', token_type: 'symbol')
    compile_expression
    process(token: ')', token_type: 'symbol')
    process(token: '{', token_type: 'symbol')
    compile_statements
    process(token: '}', token_type: 'symbol')
    if @tokenizer.peek_token == 'else'
      process(token: 'else', token_type: 'keyword')
      process(token: '{', token_type: 'symbol')
      compile_statements
      process(token: '}', token_type: 'symbol')
    end
    descend
    output('</ifStatement>')
  end

  def compile_while #TODO
    output('<whileStatement>')
    ascend
    process(token: 'while', token_type: 'keyword')
    process(token: '(', token_type: 'symbol')
    compile_expression
    process(token: ')', token_type: 'symbol')
    process(token: '{', token_type: 'symbol')
    compile_statements
    process(token: '}', token_type: 'symbol')
    descend
    output('</whileStatement>')
  end

  def compile_do #TODO
    output('<doStatement>')
    ascend
    process(token: 'do', token_type: 'keyword')
    compile_subroutine_call
    process(token: ';', token_type: 'symbol')
    descend
    output('</doStatement>')
  end

  def compile_subroutine_call #TODO
    # Subroutine call does not have its own enclosing tag
    process(token_type: 'identifier')

    regular_subroutine_call = lambda {
      process(token: '(', token_type: 'symbol')
      compile_expression_list
      process(token: ')', token_type: 'symbol')
    }

    class_or_object_subroutine_call = lambda {
      process(token: '.', token_type: 'symbol')
      process(token_type: 'identifier')
      process(token: '(', token_type: 'symbol')
      compile_expression_list
      process(token: ')', token_type: 'symbol')
    }

    process_or(regular_subroutine_call, class_or_object_subroutine_call)
  end

  def compile_return #TODO
    output('<returnStatement>')
    ascend
    process(token: 'return', token_type: 'keyword')
    compile_expression if @tokenizer.peek_token != ';'
    process(token: ';', token_type: 'symbol')
    descend
    output('</returnStatement>')
  end

  def compile_expression #TODO
    output('<expression>')
    ascend
    compile_term
    op = %w[+ - * / & | < > =]

    while op.include?(@tokenizer.peek_token)
      process(tokens: op, token_type: 'symbol')
      compile_term
    end

    descend
    output('</expression>')
  end

  def compile_term #TODO
    output('<term>')
    ascend
    case @tokenizer.peek_token_type
    when 'integerConstant'
      process(token_type: 'integerConstant')
    when 'stringConstant'
      process(token_type: 'stringConstant')
    when 'keyword' # true false null this
      process(tokens: %w[true false null this], token_type: 'keyword')
    when 'identifier' # variable name or variable name [expression]

      # We have to see if this is a varName, varName[expression], or subroutineCall. To know this, we must check
      # if the symbol after the identifier is a ( or .
      @tokenizer.mark
      @tokenizer.advance
      peeked_peeked_token = @tokenizer.peek_token
      @tokenizer.rewind

      if %w[( .].include?(peeked_peeked_token)
        compile_subroutine_call
      else
        process(token_type: 'identifier')
        if @tokenizer.peek_token == '['
          process(token: '[', token_type: 'symbol')
          compile_expression
          process(token: ']', token_type: 'symbol')
        end
      end
    when 'symbol'
      if @tokenizer.peek_token == '('
        process(token: '(', token_type: 'symbol')
        compile_expression
        process(token: ')', token_type: 'symbol')
      elsif %w[~ -].include?(@tokenizer.peek_token)
        process(tokens: %w[~ -], token_type: 'symbol')
        compile_term
      end
    else
      raise ProcessingError,
            "Could not compile term with peeked token '#{@tokenizer.peek_token}' and type '#{@tokenizer.peek_token_type}'"
    end
    descend
    output('</term>')
  end

  def compile_expression_list #TODO
    output('<expressionList>')
    ascend
    while @tokenizer.peek_token != ')'
      compile_expression

      process(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end
    descend
    output('</expressionList>')
  end

  def ascend
    @current_depth += 1
  end

  def descend
    @current_depth -= 1
  end

  def process_or(first_lambda, second_lambda)
    @tokenizer.mark
    first_lambda.call
  rescue ProcessingError => e
    @tokenizer.rewind
    second_lambda.call
  end

  def process_type
    variable_types = %w[int char boolean]
    if variable_types.include?(@tokenizer.peek_token)
      process(tokens: variable_types, token_type: 'keyword')
    elsif @tokenizer.peek_token_type == 'identifier'
      process(token_type: 'identifier')
    else
      @tokenizer.advance # Need to advance as process_or relies on it
      raise ProcessingError,
            "Error when inferring variable type from token '#{@tokenizer.peek_token}' with type '#{@tokenizer.peek_token_type}'"
    end
  end

  def expect(token_type: nil, token: nil, tokens: nil)
    if !token.nil? && @tokenizer.peek_token != token
      raise ProcessingError, "Token '#{@tokenizer.peek_token}' did not match expected token '#{token}'"
    end

    if !tokens.nil? && !tokens.include?(@tokenizer.peek_token)
      raise ProcessingError, "Token '#{@tokenizer.peek_token}' did not match any of the expected tokens '#{tokens}'"
    end

    unless !token_type.nil? && token_type == @tokenizer.peek_token_type
      raise ProcessingError,
            "Token type #{@tokenizer.peek_token_type} did not match expected token type '#{token_type}' for token '#{@tokenizer.peek_token}'"
    end
  end

  def expect_type
    variable_types = %w[int char boolean]
    if variable_types.include?(@tokenizer.peek_token)
      expect(tokens: variable_types, token_type: 'keyword')
    elsif @tokenizer.peek_token_type == 'identifier'
      expect(token_type: 'identifier')
    else
      @tokenizer.advance # Need to advance as process_or relies on it
      raise ProcessingError,
            "Error when inferring variable type from token '#{@tokenizer.peek_token}' with type '#{@tokenizer.peek_token_type}'"
    end
  end

  def advance_and_get
    @tokenizer.advance
    @tokenizer.current_token
  end

  # Looks up the variable with a given name and returns [type, kind, index]
  def look_up(name)
    if @subroutine_symbol_table.has_named(name)
      type = @subroutine_symbol_table.type_of(name)
      kind = @subroutine_symbol_table.kind_of(name)
      index = @subroutine_symbol_table.index_of(name)
      [type, kind, index]
    elsif @class_symbol_table.has_named(name)
      type = @class_symbol_table.type_of(name)
      kind = @class_symbol_table.kind_of(name)
      index = @class_symbol_table.index_of(name)
      [type, kind, index]
    else
      raise "Could not find variable #{name} in symbol tables."
    end
  end

  def process(token_type: nil, token: nil, tokens: nil)
    @tokenizer.advance

    if !token.nil? && @tokenizer.current_token != token
      raise ProcessingError, "Token '#{@tokenizer.current_token}' did not match expected token '#{token}'"
    end

    if !tokens.nil? && !tokens.include?(@tokenizer.current_token)
      raise ProcessingError, "Token '#{@tokenizer.current_token}' did not match any of the expected tokens '#{tokens}'"
    end

    unless !token_type.nil? && token_type == @tokenizer.token_type
      raise ProcessingError,
            "Token type '#{@tokenizer.token_type}' did not match expected token type '#{token_type}' for token '#{@tokenizer.current_token}'"
    end

    output(@tokenizer.xml_element)
  end

  def output(str)
    output_str = String.new

    @current_depth.times do
      INDENT_SPACES.times do
        output_str << ' '
      end
    end

    output_str << str

    @code << output_str << "\n"
  end
end
