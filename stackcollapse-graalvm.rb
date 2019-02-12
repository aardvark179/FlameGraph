#!/usr/bin/env ruby

require 'json'

SOURCE_INFO = ARGV.delete '--source'
TIMESTAMP_ORDER = ARGV.delete '--timestamp-order'

data = ARGF.read.lines.find { |line|
  line.start_with?('{"') and line.include?('"tool":')
}
abort "Could not find JSON in input" unless data
data = JSON.load(data)

def method_name(method)
  name = method.fetch("root_name")
  name = name.inspect[1...-1]
  if SOURCE_INFO
    source_section = method.fetch("source_section")
    source_name = source_section["source_name"]
    start_line = source_section["start_line"]
    end_line = source_section["end_line"]
    formatted_line = start_line == end_line ? start_line : "#{start_line}-#{end_line}"
    name = "#{name} #{source_name}:#{formatted_line}"
  end
  # Remove ';' as that character is reserved for collapsed stacks
  name.gsub(';', '')
end

def gather_samples(data, stack, samples = [])
  data.each do |method|
    stack.push method_name(method)
    method.fetch("self_hit_times").each do |time|
      samples << [stack.dup, time]
    end
    gather_samples(method.fetch("children"), stack, samples)
    stack.pop
  end
  samples
end

def dump(data, stack)
  data.each do |method|
    stack.push method_name(method)
    puts "#{stack.join(';')} #{method.fetch("self_hit_count")}"
    dump(method.fetch("children"), stack)
    stack.pop
  end
end

tool = data.fetch("tool")
case tool
when "cpusampler"
  profile = data.fetch("profile")
  abort "Need hit times (--cpusampler.GatherHitTimes)" if TIMESTAMP_ORDER && !data["gathered_hit_times"]
  stack = []

  profile.each do |thread|
    name = thread.fetch("thread")
    samples = thread.fetch("samples")

    stack.push name
    if TIMESTAMP_ORDER
      gather_samples(samples, stack).sort_by { |stack, time| time }.each do |stack, time|
        puts "#{stack.join(';')} 1"
      end
    else
      dump(samples, stack)
    end
    stack.pop
  end
when "cputracer"
  profile = data.fetch("profile")

  profile.each do |method|
    puts "#{method_name(method)} #{method.fetch("count")}"
  end
else
  abort "Unknown tool: #{tool}"
end
