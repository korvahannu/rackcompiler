# frozen_string_literal: true

require_relative 'vm_writer'
require_relative 'symbol_table'
require_relative 'character_set'

class ProcessingError < StandardError
end

class CompilationEngine
  INDENT_SPACES = 2

  def initialize(input_filepath, output_filepath)
    @input_filepath = input_filepath
    @output_filepath = output_filepath

    @writer = VMWriter.new
    @class_symbol_table = SymbolTable.new
    @subroutine_symbol_table = SymbolTable.new

    @tokenizer = Tokenizer.new(@input_filepath)
    raise 'Empty tokenizer ' unless @tokenizer.more_tokens?
  end

  def compile
    compile_class

    File.open(@output_filepath, 'w') do |output_file|
      output_file.puts @writer.code.strip
    end

    @tokenizer.reset
  end

  private

  def compile_class
    expect_and_advance(token: 'class', token_type: 'keyword')
    expect(token_type: 'identifier')
    @class_name = advance_and_get
    expect_and_advance(token: '{', token_type: 'symbol')
    compile_class_var_dec while %w[static field].include?(@tokenizer.peek_token)
    compile_subroutine while %w[constructor function method].include?(@tokenizer.peek_token)
    expect_and_advance(token: '}', token_type: 'symbol')
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
      expect_and_advance(token: ',', token_type: 'symbol')
      name = advance_and_get
      @class_symbol_table.define(name, type, kind)
    end
    expect_and_advance(token: ';', token_type: 'symbol')
  end

  def compile_subroutine
    @subroutine_symbol_table = @subroutine_symbol_table.append
    @subroutine_symbol_table.define('this', @class_name, :arg) if @tokenizer.peek_token == 'method'
    expect(tokens: %w[constructor function method], token_type: 'keyword')
    subroutine_type = advance_and_get
    expect_or -> { expect_type }, -> { expect(token: 'void', token_type: 'keyword') }
    @return_type = advance_and_get # compile_return needs this for void types
    function_name = advance_and_get
    expect_and_advance(token: '(', token_type: 'symbol')
    compile_parameter_list
    expect_and_advance(token: ')', token_type: 'symbol')

    expect_and_advance(token: '{', token_type: 'symbol')
    variable_count = 0
    variable_count += compile_var_dec while @tokenizer.peek_token == 'var'

    # Write the function declaration only here as we need the count of local variables
    @writer.write_function("#{@class_name}.#{function_name}", variable_count)
    @writer.indent

    if subroutine_type == 'constructor'
      object_size = @class_symbol_table.size_of(:field)
      @writer.write_push('constant', object_size)
      @writer.write_call('Memory.alloc', 1)
      @writer.write_pop('pointer', 0)
    end

    if subroutine_type == 'method'
      @writer.write_push('argument', 0) # Align this
      @writer.write_pop('pointer', 0)
    end
    compile_statements
    expect_and_advance(token: '}', token_type: 'symbol')
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
      expect_and_advance(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end
  end

  def compile_var_dec
    variable_count = 0
    expect_and_advance(token: 'var', token_type: 'keyword')
    expect_type
    type = advance_and_get

    while @tokenizer.peek_token != ';'
      variable_count += 1
      identifier = advance_and_get
      @subroutine_symbol_table.define(identifier, type, :var)
      expect_and_advance(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end

    expect_and_advance(token: ';', token_type: 'symbol')
    variable_count
  end

  def compile_statements
    while %w[let if while do return].include?(@tokenizer.peek_token)
      compile_let if @tokenizer.peek_token == 'let'
      compile_if if @tokenizer.peek_token == 'if'
      compile_while if @tokenizer.peek_token == 'while'
      compile_do if @tokenizer.peek_token == 'do'
      compile_return if @tokenizer.peek_token == 'return'
    end
  end

  def compile_let
    expect_and_advance(token: 'let', token_type: 'keyword')
    expect(token_type: 'identifier')
    name = advance_and_get
    _, _, index = look_up(name)

    if @tokenizer.peek_token == '['
      @writer.write_push(segment_name_for(name), index)

      expect_and_advance(token: '[', token_type: 'symbol')
      compile_expression
      expect_and_advance(token: ']', token_type: 'symbol')

      @writer.write_arithmetic('add') # *(arr + 1) is on top of stack now

      expect_and_advance(token: '=', token_type: 'symbol')
      compile_expression
      expect_and_advance(token: ';', token_type: 'symbol')

      @writer.write_pop('temp', 0) # store result of expression2 to to temp 0
      @writer.write_pop('pointer', 1) # Align segment THAT with the target address
      @writer.write_push('temp', 0)
      @writer.write_pop('that', 0) # Push the value of array[x] to stack
    else
      expect_and_advance(token: '=', token_type: 'symbol')
      compile_expression
      expect_and_advance(token: ';', token_type: 'symbol')
      @writer.write_pop(segment_name_for(name), index)
    end
  end

  def compile_if
    label1 = "IF_EXP#{unique_identifier_if}"
    label2 = "IF_END-#{unique_identifier_if}"
    expect_and_advance(token: 'if', token_type: 'keyword')
    expect_and_advance(token: '(', token_type: 'symbol')
    compile_expression
    @writer.write_arithmetic('not')
    @writer.write_if(label1)
    expect_and_advance(token: ')', token_type: 'symbol')
    expect_and_advance(token: '{', token_type: 'symbol')
    compile_statements
    @writer.write_goto(label2)
    @writer.write_label(label1)
    expect_and_advance(token: '}', token_type: 'symbol')
    if @tokenizer.peek_token == 'else'
      expect_and_advance(token: 'else', token_type: 'keyword')
      expect_and_advance(token: '{', token_type: 'symbol')
      compile_statements
      expect_and_advance(token: '}', token_type: 'symbol')
    end
    @writer.write_label(label2)
  end

  def compile_while
    label1 = "WHILE_EXP#{unique_identifier_while}"
    label2 = "WHILE_END#{unique_identifier_while}"
    expect_and_advance(token: 'while', token_type: 'keyword')
    expect_and_advance(token: '(', token_type: 'symbol')
    @writer.write_label(label1)
    compile_expression
    @writer.write_arithmetic('not')
    @writer.write_if(label2)
    expect_and_advance(token: ')', token_type: 'symbol')
    expect_and_advance(token: '{', token_type: 'symbol')
    compile_statements
    @writer.write_goto(label1)
    @writer.write_label(label2)
    expect_and_advance(token: '}', token_type: 'symbol')
  end

  def compile_do
    expect_and_advance(token: 'do', token_type: 'keyword')
    compile_subroutine_call
    @writer.write_pop('temp', 0)
    expect_and_advance(token: ';', token_type: 'symbol')
  end

  def compile_subroutine_call
    # Subroutine call does not have its own enclosing tag
    expect(token_type: 'identifier')
    name = advance_and_get

    if @tokenizer.peek_token == '('
      expect_and_advance(token: '(', token_type: 'symbol')
      @writer.write_push('pointer', 0)
      argument_count = compile_expression_list
      expect_and_advance(token: ')', token_type: 'symbol')
      @writer.write_call("#{@class_name}.#{name}", argument_count + 1)
    elsif expect_and_advance(token: '.', token_type: 'symbol')
      expect(token_type: 'identifier')
      method_name = advance_and_get

      type, _, index = look_up(name)
      is_method_call = !type.nil?

      @writer.write_push(segment_name_for(name), index) if is_method_call

      expect_and_advance(token: '(', token_type: 'symbol')
      argument_count = compile_expression_list
      expect_and_advance(token: ')', token_type: 'symbol')

      name = type unless type.nil?

      @writer.write_call("#{name}.#{method_name}", is_method_call ? argument_count + 1 : argument_count)
    end
  end

  def compile_return
    expect_and_advance(token: 'return', token_type: 'keyword')
    compile_expression if @tokenizer.peek_token != ';'
    @writer.write_push('constant', 0) if @return_type == 'void'
    @writer.write_return
    expect_and_advance(token: ';', token_type: 'symbol')
  end

  def compile_expression
    compile_term
    op = %w[+ - * / & | < > =]

    while op.include?(@tokenizer.peek_token)
      expect(tokens: op, token_type: 'symbol')
      symbol = advance_and_get
      compile_term
      case symbol
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
      else
        raise "Fatal error! Missing code path for #{symbol}"
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
      case token
      when 'true'
        @writer.write_push('constant', 0)
        @writer.write_arithmetic('not')
      when 'false', 'null'
        @writer.write_push('constant', 0)
      when 'this'
        @writer.write_push('pointer', 0)
      else
        raise "Fatal error! Missing code path for #{token}"
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
        _, _, index = look_up(name)
        @writer.write_push(segment_name_for(name), index)

        # This is for arrays
        if @tokenizer.peek_token == '['
          expect_and_advance(token: '[', token_type: 'symbol')
          compile_expression
          expect_and_advance(token: ']', token_type: 'symbol')
          @writer.write_arithmetic('add') # *(arr + 1) is on top of stack now
          @writer.write_pop('pointer', 1) # Align segment that with the target address
          @writer.write_push('that', 0) # Push the value of array[x] to stack
        end
      end
    when 'symbol'
      if @tokenizer.peek_token == '('
        expect_and_advance(token: '(', token_type: 'symbol')
        compile_expression
        expect_and_advance(token: ')', token_type: 'symbol')
      elsif %w[~ -].include?(@tokenizer.peek_token)
        expect(tokens: %w[~ -], token_type: 'symbol')
        token = advance_and_get
        compile_term
        @writer.write_arithmetic('neg') if token == '-'
        @writer.write_arithmetic('not') if token == '~'
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
      expect_and_advance(token: ',', token_type: 'symbol') if @tokenizer.peek_token == ','
    end
    expression_count
  end

  # A poor man approach for expecting two options
  # Takes in two lambdas with expectations. If the first fails, tries to second one
  # If the second one also fails, error falls to caller
  def expect_or(first_lambda, second_lambda)
    first_lambda.call
  rescue ProcessingError => _e
    second_lambda.call
  end

  # Checks the next token and asserts/checks that it is what is expected
  # Advances tokenizer
  def expect_and_advance(token_type: nil, token: nil, tokens: nil)
    expect(token_type: token_type, token: token, tokens: tokens)
    @tokenizer.advance
    @tokenizer.current_token
  end

  # Checks the next token and asserts/checks that it is what is expected
  # Does not advance tokenizer
  def expect(token_type: nil, token: nil, tokens: nil)
    if !token.nil? && @tokenizer.peek_token != token
      raise ProcessingError, "Token '#{@tokenizer.peek_token}' did not match expected token '#{token}'"
    end

    if !tokens.nil? && !tokens.include?(@tokenizer.peek_token)
      raise ProcessingError, "Token '#{@tokenizer.peek_token}' did not match any of the expected tokens '#{tokens}'"
    end

    return if !token_type.nil? && token_type == @tokenizer.peek_token_type

    raise ProcessingError, "Token type #{@tokenizer.peek_token_type} did not match expected token type '#{token_type}' for token '#{@tokenizer.peek_token}'"
  end

  # A helper method for expecting that the next token is a variable type (int char boolean) or an identifier
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

  # Advances the tokenizer and returns the current value
  def advance_and_get
    @tokenizer.advance
    @tokenizer.current_token
  end

  # Looks up the variable with a given name and returns [type, kind, index].
  # Look up searches the current subroutine symbol table, and class symbol table.
  def look_up(name)
    if @subroutine_symbol_table.named?(name)
      type = @subroutine_symbol_table.type_of(name)
      kind = @subroutine_symbol_table.kind_of(name)
      index = @subroutine_symbol_table.index_of(name)
      return [type, kind, index]
    elsif @class_symbol_table.named?(name)
      type = @class_symbol_table.type_of(name)
      kind = @class_symbol_table.kind_of(name)
      index = @class_symbol_table.index_of(name)
      return [type, kind, index]
    end
    nil
  end

  # Returns the segment name for a variable of given name (static, local, argument, this)
  def segment_name_for(name)
    if @subroutine_symbol_table.named?(name)
      return @subroutine_symbol_table.segment_name_for(name)
    elsif @class_symbol_table.named?(name)
      return @class_symbol_table.segment_name_for(name)
    end

    nil
  end

  # Returns an unique number, indented for labeling if -labels
  def unique_identifier_if
    @unique_identifier = -1 if @unique_identifier.nil?
    @unique_identifier += 1
  end

  # Returns an unique number, indented for labeling while -loops
  def unique_identifier_while
    @unique_identifier = -1 if @unique_identifier.nil?
    @unique_identifier += 1
  end
end
