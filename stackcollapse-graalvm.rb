#!/usr/bin/env ruby

require 'json'

input = ARGF.read.lines
input.shift until input.first.start_with?('{"')
input = input.join
data = JSON.load(input)

def gather_samples(data, stack = [], samples = [])
  data.each do |method|
    stack.push method["root_name"]
    method["self_hit_times"].each do |time|
      samples << [stack.dup, time]
    end
    gather_samples(method["children"], stack, samples)
    stack.pop
  end
  samples
end

def dump(data, stack = [])
  data.each do |method|
    stack.push method["root_name"]
    puts "#{stack.join(';')} #{method["self_hit_count"]}"
    dump(method["children"], stack)
    stack.pop
  end
end

tool = data["tool"]
case tool
when "cpusampler"
  data = data["profile"].flat_map { |thread| thread["samples"] }

  timestamp_order = ARGV.delete '--timestamp-order'
  if timestamp_order
    gather_samples(data).sort_by { |stack, time| time }.each do |stack, time|
      puts "#{stack.join(';')} 1"
    end
  else
    dump(data)
  end
when "cputracer"
  data = data["profile"]

  data.each do |method|
    puts "#{method["root_name"]} #{method["count"]}"
  end
else
  abort "Unknown tool: #{tool}"
end
