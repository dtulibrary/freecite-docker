require 'freecite'
require 'json'

class FreeciteController < Sinatra::Base
  get '/search' do
    content_type 'application/json'

    query = params["q"] || ""
    JSON.generate(CRFParser.new.parse_string(query) || {})
  end
end
