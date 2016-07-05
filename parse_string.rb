$LOAD_PATH.unshift(File.dirname(__FILE__) + "/lib")
require 'freecite'

require 'json'
puts JSON.generate(CRFParser.new.parse_string(ARGV.join(" ")))

#require 'pp'
#pp CRFParser.new.parse_string(ARGV.join(" "))
