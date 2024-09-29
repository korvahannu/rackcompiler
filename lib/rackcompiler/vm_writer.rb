# frozen_string_literal: true

class VMWriter
  INDENT_SPACES = 2
  ARITHMETIC_COMMANDS = %w[add sub neg eq gt lt and or not]

  attr_accessor :code

  def initialize
    @code = String.new
    @indent = 0
  end

  def write_push(segment, index)
    write_line("push #{segment} #{index}")
  end

  def write_pop(segment, index)
    write_line("pop #{segment} #{index}")
  end

  def write_arithmetic(command)
    command.downcase!

    raise "Unknown arithmetic command #{command}" unless ARITHMETIC_COMMANDS.include?(command)

    write_line("#{command}")
  end

  def write_label(label)
    write_line("label #{label}")
  end

  def write_goto(label)
    write_line("goto #{label}")
  end

  def write_if(label)
    write_line("if-goto #{label}")
  end

  def write_call(name, argument_count)
    write_line("call #{name} #{argument_count}")
  end

  def write_function(name, parameter_count)
    write_line("function #{name} #{parameter_count}")
  end

  def write_return
    write_line("return")
  end

  def indent
    @indent += 1
  end

  def undent
    @indent -= 1
  end

  private

  def write_line(line)
    @indent.times do
      INDENT_SPACES.times do
        @code << ' '
      end
    end

    @code << line
    @code << "\n"
  end
end