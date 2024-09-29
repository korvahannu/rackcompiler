# frozen_string_literal: true

require_relative 'vm_writer'
require_relative 'symbol_table'
require_relative 'character_set'

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

    File.open(@output_filepath, 'w') do |output_file|
      output_file.puts @writer.code.strip
    end

    @tokenizer.reset
  end

  private

  def compile_class
    output('<class>')
    ascend
    process(token: 'class', token_type: 'keyword')
    expect(token_type: 'identifier')
    @class_name = advance_and_get
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
    @subroutine_symbol_table.define('this', @class_name, :arg) if @tokenizer.peek_token == 'method'
    process(tokens: %w[constructor function method], token_type: 'keyword')
    expect_or -> { expect_type }, -> { expect(token: 'void', token_type: 'keyword') }
    @return_type = advance_and_get # compile_return needs this for void types
    function_name = advance_and_get
    process(token: '(', token_type: 'symbol')
    parameter_count = compile_parameter_list
    process(token: ')', token_type: 'symbol')

    process(token: '{', token_type: 'symbol')
    variable_count = 0
    variable_count += compile_var_dec while @tokenizer.peek_token == 'var'

    # Write the function declaration only here as we need the count of local variables
    @writer.write_function("#{@class_name}.#{function_name}", variable_count)
    @writer.indent

    compile_statements
    process(token: '}', token_type: 'symbol')
    @writer.undent
    @writer.write_empty_line
    @subroutine_symbol_table = @subroutine_symbol_table.reject
  end

  def compile_parameter_list
    while @tokenizer.peek_token != ')'
      expect_type
      type = advance_and_get
      expect(token_type: 'identifier')
      name = advance_and_get
      @subroutine_symbol_table.define(name, type, :arg)
      process(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end
  end

  def compile_var_dec
    variable_count = 0
    process(token: 'var', token_type: 'keyword')
    expect_type
    type = advance_and_get

    while @tokenizer.peek_token != ';'
      variable_count += 1
      identifier = advance_and_get
      @subroutine_symbol_table.define(identifier, type, :var)
      process(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end

    process(token: ';', token_type: 'symbol')
    variable_count
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

  def compile_let
    process(token: 'let', token_type: 'keyword')
    expect(token_type: 'identifier')
    name = advance_and_get
    _, kind, index = look_up(name)

    if @tokenizer.peek_token == '['
      case kind
      when :static
        @writer.write_push('static', index)
      when :field
        @writer.write_push('this', index)
      when :var
        @writer.write_push('local', index)
      else
        @writer.write_push('argument', index)
      end

      process(token: '[', token_type: 'symbol')
      compile_expression
      process(token: ']', token_type: 'symbol')

      @writer.write_arithmetic('add') # *(arr + 1) is on top of stack now
      @writer.write_pop('pointer', 1) # Align segment that with the target address

      process(token: '=', token_type: 'symbol')
      compile_expression
      process(token: ';', token_type: 'symbol')

      @writer.write_pop('that', 0) # Push the expression result to array[...]
    else
      process(token: '=', token_type: 'symbol')
      compile_expression
      process(token: ';', token_type: 'symbol')

      case kind
      when :static
        @writer.write_pop('static', index)
      when :field
        @writer.write_pop('this', index)
      when :var
        @writer.write_pop('local', index)
      else
        @writer.write_pop('argument', index)
      end
    end
  end

  def compile_if
    label1 = "IF_EXP#{unique_identifier_if}"
    label2 = "IF_END-#{unique_identifier_if}"
    process(token: 'if', token_type: 'keyword')
    process(token: '(', token_type: 'symbol')
    compile_expression
    @writer.write_arithmetic('not')
    @writer.write_if(label1)
    process(token: ')', token_type: 'symbol')
    process(token: '{', token_type: 'symbol')
    compile_statements
    @writer.write_goto(label2)
    @writer.write_label(label1)
    process(token: '}', token_type: 'symbol')
    if @tokenizer.peek_token == 'else'
      process(token: 'else', token_type: 'keyword')
      process(token: '{', token_type: 'symbol')
      compile_statements
      process(token: '}', token_type: 'symbol')
    end
    @writer.write_label(label2)
  end

  def compile_while
    label1 = "WHILE_EXP#{unique_identifier_while}"
    label2 = "WHILE_END#{unique_identifier_while}"
    process(token: 'while', token_type: 'keyword')
    process(token: '(', token_type: 'symbol')
    @writer.write_label(label1)
    compile_expression
    @writer.write_arithmetic('not')
    @writer.write_if(label2)
    process(token: ')', token_type: 'symbol')
    process(token: '{', token_type: 'symbol')
    compile_statements
    @writer.write_goto(label1)
    @writer.write_label(label2)
    process(token: '}', token_type: 'symbol')
  end

  def compile_do
    process(token: 'do', token_type: 'keyword')
    compile_subroutine_call
    @writer.write_pop('temp', 0)
    process(token: ';', token_type: 'symbol')
  end

  def compile_subroutine_call
    # Subroutine call does not have its own enclosing tag
    expect(token_type: 'identifier')
    name = advance_and_get
    @argument_count = 0

    regular_subroutine_call = lambda {
      process(token: '(', token_type: 'symbol')
      @argument_count = compile_expression_list
      process(token: ')', token_type: 'symbol')
    }

    class_or_object_subroutine_call = lambda {
      process(token: '.', token_type: 'symbol')
      expect(token_type: 'identifier')
      method_name = advance_and_get
      @method_name = method_name

      process(token: '(', token_type: 'symbol')
      @argument_count = compile_expression_list
      process(token: ')', token_type: 'symbol')
    }

    process_or(regular_subroutine_call, class_or_object_subroutine_call)

    if @method_name.nil?
      @writer.write_call("#{@class_name}.#{name} ", @argument_count)
    else
      @writer.write_call("#{name}.#{@method_name}", @argument_count)
      @method_name = nil
    end
  end

  def compile_return
    process(token: 'return', token_type: 'keyword')
    compile_expression if @tokenizer.peek_token != ';'
    @writer.write_push('constant', 0) if @return_type == 'void'
    @writer.write_return
    process(token: ';', token_type: 'symbol')
  end

  def compile_expression
    compile_term
    op = %w[+ - * / & | < > =]

    while op.include?(@tokenizer.peek_token)
      expect(tokens: op, token_type: 'symbol')
      symbol = advance_and_get
      compile_term
      case (symbol)
      when '+'
        @writer.write_arithmetic('add')
      when '-'
        @writer.write_arithmetic('sub')
      when '*'
        @writer.write_call('Math.multiply', 2)
      when '/'
        @writer.write_call('Math.divide', 2)
      when '&'
        @writer.write_arithmetic('and')
      when '|'
        @writer.write_arithmetic('or')
      when '<'
        @writer.write_arithmetic('lt')
      when '>'
        @writer.write_arithmetic('gt')
      when '='
        @writer.write_arithmetic('eq')
      end
    end
  end

  def compile_term
    case @tokenizer.peek_token_type
    when 'integerConstant'
      expect(token_type: 'integerConstant')
      @writer.write_push('constant', advance_and_get)
    when 'stringConstant'
      expect(token_type: 'stringConstant')
      parsed_string = advance_and_get[1...-1] # remove the outer "..." from the string constant
      @writer.write_push('constant', parsed_string.size)
      @writer.write_call('String.new', 1)
      parsed_string.each_char do |char|
        @writer.write_push('constant', CharacterSet.to_number(char))
        @writer.write_call('String.appendChar', 2)
      end
    when 'keyword' # true false null this
      expect(tokens: %w[true false null this], token_type: 'keyword')
      token = advance_and_get
      case (token)
      when 'true'
        @writer.write_push('constant', 0)
        @writer.write_arithmetic('not')
      when 'false', 'null'
        @writer.write_push('constant', 0)
      when 'this'
        @writer.write_push('pointer', 0)
      end
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
        expect(token_type: 'identifier')
        name = advance_and_get
        _, kind, index = look_up(name)

        case kind
        when :static
          @writer.write_push('static', index)
        when :field
          @writer.write_push('this', index)
        when :var
          @writer.write_push('local', index)
        else
          @writer.write_push('argument', index)
        end

        # This is for arrays
        if @tokenizer.peek_token == '['
          process(token: '[', token_type: 'symbol')
          compile_expression
          process(token: ']', token_type: 'symbol')
          @writer.write_arithmetic('add') # *(arr + 1) is on top of stack now
          @writer.write_pop('pointer', 1) # Align segment that with the target address
          @writer.write_push('that', 0) # Push the value of array[x] to stack
        end
      end
    when 'symbol'
      if @tokenizer.peek_token == '('
        process(token: '(', token_type: 'symbol')
        compile_expression
        process(token: ')', token_type: 'symbol')
      elsif %w[~ -].include?(@tokenizer.peek_token)
        expect(tokens: %w[~ -], token_type: 'symbol')
        token = advance_and_get
        compile_term
        @writer.write_arithmetic('neg') if token == "-"
        @writer.write_arithmetic('not') if token == "~"
      end
    else
      raise ProcessingError,
            "Could not compile term with peeked token '#{@tokenizer.peek_token}' and type '#{@tokenizer.peek_token_type}'"
    end
  end

  def compile_expression_list
    expression_count = 0
    while @tokenizer.peek_token != ')'
      expression_count += 1
      compile_expression
      process(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end
    expression_count
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

  def expect_or(first_lambda, second_lambda)
    first_lambda.call
  rescue ProcessingError => e
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
      return [type, kind, index]
    elsif @class_symbol_table.has_named(name)
      type = @class_symbol_table.type_of(name)
      kind = @class_symbol_table.kind_of(name)
      index = @class_symbol_table.index_of(name)
      return [type, kind, index]
    end
    nil
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

  def unique_identifier_if
    @unique_identifier = -1 if @unique_identifier.nil?
    @unique_identifier += 1
    @unique_identifier
  end

  def unique_identifier_while
    @unique_identifier = -1 if @unique_identifier.nil?
    @unique_identifier += 1
    @unique_identifier
  end
end
