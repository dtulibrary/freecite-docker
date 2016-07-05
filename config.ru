$LOAD_PATH.unshift(
  File.dirname(__FILE__) + "/lib",
  File.dirname(__FILE__) + "/controllers")

require 'sinatra/base'
require 'freecite_controller'

map('/citation') { run FreeciteController }
