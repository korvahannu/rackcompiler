# frozen_string_literal: true

class Keyword
  KEYWORDS = %w[class method function constructor int boolean char void var static field let do if else while return
                true false null this].freeze

  class << self
    def is_keyword(word)
      KEYWORDS.include?(word)
    end
  end
end

class Symbol
  SYMBOLS = %w[{ } ( ) [ ] . , ; + - * / & | < > = ~].freeze

  class << self
    def is_symbol(word)
      SYMBOLS.include?(word)
    end
  end
end

class Tokenizer
  def initialize(filepath)
    @tokens = TokenParser.new(filepath).parse.tokens
    @index = -1
  end

  def has_more_tokens?
    @index + 1 < @tokens.length
  end

  def advance
    raise 'No more tokens to process' unless has_more_tokens?

    @index += 1
  end

  def reset
    @index = -1
  end

  def current_token
    @tokens[@index]
  end

  def token_type
    raise 'Current token is nil' if current_token.nil?

    return 'keyword' if Keyword.is_keyword(current_token)
    return 'symbol' if Symbol.is_symbol(current_token)

    integer_constant = number_or_nil(current_token)

    unless integer_constant.nil?
      raise "Integer constant '#{integer_constant}' outside of allowed range (0-32767)" unless integer_constant.between?(
        0, 32_767
      )

      return 'integerConstant'
    end

    if current_token.start_with?('"')
      return 'stringConstant' if current_token.end_with?('"')

      raise "Corrupted token encountered: '#{current_token}'"

    end

    return 'identifier' unless current_token.match?(/\A\d/)

    raise "Unable to determine token type for '#{current_token}'"
  end

  def keyword
    raise 'Cannot get keyword when token type is not of keyword type' if token_type != 'keyword'

    current_token
  end

  def symbol
    raise 'Cannot get symbol when token type is not of symbol type' if token_type != 'symbol'

    case current_token
    when '<'
      '&lt;'
    when '>'
      '&gt;'
    when '"'
      '&quot;'
    when '&'
      '&amp;'
    else
      current_token
    end
  end

  def identifier
    raise 'Cannot get identifier when token type is not of identifier type' if token_type != 'identifier'

    current_token
  end

  def int_val
    raise 'Cannot get integer value when token type is not of integerConstant type' if token_type != 'integerConstant'

    number_or_nil(current_token)
  end

  def string_val
    raise 'Cannot get string value when token type is not of stringConstant type' if token_type != 'stringConstant'

    current_token[1...-1]
  end

  def write_xml(output_filepath)
    File.open(output_filepath, 'w') do |output_file|
      output_file.puts '<tokens>'
      while has_more_tokens?
        advance
        output_file.puts xml_element
      end
      output_file.puts '</tokens>'
    end

    reset
  end

  def xml_element
    case token_type
    when 'keyword'
      content = keyword
    when 'symbol'
      content = symbol
    when 'integerConstant'
      content = int_val
    when 'stringConstant'
      content = string_val
    when 'identifier'
      content = identifier
    else
      raise "Encountered unknown token type #{token_type}"
    end

    "<#{token_type}> #{content} </#{token_type}>"
  end

  private

  def number_or_nil(string)
    Integer(string || '')
  rescue ArgumentError
    nil
  end
end

# This class is responsible for reading a line and extracting the individual tokens inside. This class has no
# understanding of the semantics. This is simply a class that takes in a file, takes all the tokens and puts them
# into an array, and returns said array for further processing.
#
# Use like this to get the tokens: TokenParser.new(filepath).parse.tokens
class TokenParser
  attr_reader :tokens

  def initialize(filepath)
    @processing_comment_block = false
    @compound_word = nil
    @tokens = []
    @filepath = filepath
  end

  def parse
    File.foreach(@filepath) do |line|
      next if line.chomp.start_with?('//')

      line.split.each do |word|
        break unless process_word(tokens, word.chomp)
      end
    end
    self
  end

  private

  # Processes a single word in a line. A word in this context is a string with no spaces in it.
  # Returns false to signal that the current line being read should be skipped, otherwise true.
  # If multiple tokens exist in a single word, for example 'if(a=true)' then this method splits it
  # and processes it as you would expect.
  def process_word(tokens, word)
    # If the word starts with // and we are not processing a comment, signal a skip line
    return false if word.start_with?('//') && !@processing_comment_block

    # If the word starts with /* we can expect a comment block or a doc block. Skip all the remaining words until
    # we encounter a */
    if word.start_with?('/*')
      @processing_comment_block = true
      return true
    end

    # */ encountered here, can stop processing a comment block
    if word.end_with?('*/')
      @processing_comment_block = false
      return true
    end

    # Don't continue if processing a comment block
    return true if @processing_comment_block

    # Compound words are string constants. Special processing needs to be applied to process them properly
    if (word.start_with?('"') || !@compound_word.nil?) && delimiter_split(word).size == 1
      @compound_word = [] if @compound_word.nil?
      @compound_word << word

      if word.end_with?('"')
        word = @compound_word.join(' ')
        @compound_word = nil
      end
    end

    # Split the word using, keeping the delimiters
    # Delimiters are: ( ) + - = < > { } . ; ----- [ ] , * / & | ~
    words_delimiter_split = delimiter_split(word)

    # If the words_delimiter_split is larger than 1, it means that this word contains multiple tokens.
    # So process each element one by one recursively.
    if words_delimiter_split.size > 1
      words_delimiter_split.each do |w|
        break unless process_word(tokens, w)
      end
    else
      return true unless @compound_word.nil?

      tokens << word
    end

    true
  end

  def delimiter_split(word)
    # Split the word using, keeping the delimiters
    # Delimiters are: ( ) + - = < > { } . ; ----- [ ] , * / & | ~
    word.split(%r{([()+\-=<>{}.;\[\],*/&|~|])}).filter { |s| !s.empty? }
  end
end
