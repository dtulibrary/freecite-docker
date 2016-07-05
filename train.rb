$LOAD_PATH.unshift(File.dirname(__FILE__) + "/lib")
require 'freecite'
CRFParser.new.train
