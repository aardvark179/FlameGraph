#!/usr/bin/env ruby

require 'json'

input = ARGF.read.lines
input.shift until input.first.start_with?('{"')
input = input.join
data = JSON.load(input)

def gather_samples(data, stack, samples = [])
  data.each do |method|
    stack.push method.fetch("root_name")
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
    stack.push method.fetch("root_name")
    puts "#{stack.join(';')} #{method.fetch("self_hit_count")}"
    dump(method.fetch("children"), stack)
    stack.pop
  end
end

tool = data.fetch("tool")
case tool
when "cpusampler"
  timestamp_order = ARGV.delete '--timestamp-order'

  data = data.fetch("profile")
  stack = []

  data.each do |thread|
    name = thread.fetch("thread")
    samples = thread.fetch("samples")

    stack.push name
    if timestamp_order
      gather_samples(samples, stack).sort_by { |stack, time| time }.each do |stack, time|
        puts "#{stack.join(';')} 1"
      end
    else
      dump(samples, stack)
    end
    stack.pop
  end
when "cputracer"
  data = data.fetch("profile")

  data.each do |method|
    puts "#{method.fetch("root_name")} #{method.fetch("count")}"
  end
else
  abort "Unknown tool: #{tool}"
end
