#!/usr/bin/env ruby

require 'json'

data = JSON.load(ARGF.read)
data = data["profile"]

data.each do |method|
  puts "#{method["root_name"]} #{method["count"]}"
end
