#!/usr/bin/env ruby

require 'json'

TIMESTAMP_ORDER = ARGV.delete '--timestamp-order'

data = ARGF.read.lines.find { |line|
  line.start_with?('{"') and line.include?('"tool":')
}
abort "Could not find JSON in input" unless data
data = JSON.load(data)

def method_name(json)
  name = json.fetch("root_name")
  name.inspect[1...-1]
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
