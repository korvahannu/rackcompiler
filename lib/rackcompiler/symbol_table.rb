# frozen_string_literal: true

class SymbolTableEntry
  attr_reader :name, :type

  def initialize(name, type)
    @type = type
    @name = name
  end
end

class SymbolTable
  def initialize(previous_symbol_table = nil)
    @previous_symbol_table = previous_symbol_table
    reset
  end

  # Creates a new symbol table and links it to this one. Returns the new table
  def append
    SymbolTable.new(self)
  end

  # Returns the previous symbol table
  def reject
    @previous_symbol_table
  end

  # Empties and resets the symbol table
  def reset
    @static = []
    @field = []
    @arg = []
    @var = []
    @mapping = {} # This map contains locations for variable names
  end

  # Adds a new variable to the table with a given name, type, and kind
  def define(name, type, kind)
    if @mapping.include?(name)
      raise "Trying to define variable #{name} of type #{type}, but it is already defined."
    end

    entries = get_entries_of_kind(kind)
    entries << SymbolTableEntry.new(name, type)
    @mapping[name] = kind
  end

  def has_named(name)
    !@mapping[name].nil?
  end

  # Returns the number of variables of the given kind currently defined in the symbol table
  def var_count(kind)
    get_entries_of_kind(kind).size
  end

  # Returns the kind of the named identifier or nil if it does not exist
  def kind_of(name)
    @mapping[name]
  end

  # Returns the type of the named identifier or nil if it does not exist
  def type_of(name)
    kind = kind_of(name)
    entries = get_entries_of_kind(kind)
    entries.each do |entry|
      return entry.type if entry.name == name
    end
    nil
  end

  def segment_name_of(name)
    kind = kind_of(name)
    case (kind)
    when :static
      'static'
    when :field
      'this'
    when :var
      'local'
    else
      'argument'
    end
  end

  # Returns the index of the named identifier or nil if it does not exist
  def index_of(name)
    kind = kind_of(name)
    entries = get_entries_of_kind(kind)
    entries.each_with_index do |entry, index|
      return index if entry.name == name
    end
    nil
  end

  def to_s
    result = String.new
    result << 'SEGMENT STATIC'
    result << "\n"
    @static.each do |entry|
      result << "#{entry.type} #{entry.name}\n"
    end
    result << "\n"
    result << 'SEGMENT FIELD'
    result << "\n"
    @field.each do |entry|
      result << "#{entry.type} #{entry.name}\n"
    end
    result << "\n"
    result << 'SEGMENT ARG'
    result << "\n"
    @arg.each do |entry|
      result << "#{entry.type} #{entry.name}\n"
    end
    result << "\n"
    result << 'SEGMENT VAR'
    result << "\n"
    @var.each do |entry|
      result << "#{entry.type} #{entry.name}\n"
    end
    result
  end

  def size_of(kind)
    case kind
    when :static
      @static.size
    when :field
      @field.size
    when :arg
      @arg.size
    when :var
      @var.size
    else
      raise "Unknown variable kind of '#{kind}' when getting entries of kind"
    end
  end

  private

  def get_entries_of_kind(kind)
    case kind
    when :static
      @static
    when :field
      @field
    when :arg
      @arg
    when :var
      @var
    else
      raise "Unknown variable kind of '#{kind}' when getting entries of kind"
    end
  end
end