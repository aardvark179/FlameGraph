#!/usr/bin/env ruby

require 'json'

def dump(data, stack)
  data.each do |method|
    stack.push method["root name"]
    puts "#{stack.join(';')} #{method["self hit count"]}"
    dump(method["children"], stack)
    stack.pop
  end
end

data = JSON.load(ARGF.read)
dump(data, [])
