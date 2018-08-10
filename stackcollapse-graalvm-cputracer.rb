#!/usr/bin/env ruby

require 'json'

data = JSON.load(ARGF.read)
data.each do |method|
  puts "#{method["root name"]} #{method["count"]}"
end
