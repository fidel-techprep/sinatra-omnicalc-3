require "sinatra"
require "sinatra/reloader"
require "http"
require "sinatra/cookies"
include Rack::Utils

# Fetch API keys from environment
GMAPS_KEY = ENV.fetch("GMAPS_KEY")
PIRATE_WEATHER_KEY = ENV.fetch("PIRATE_WEATHER_KEY")
OPENAI_API_KEY = ENV.fetch("OPENAI_API_KEY")

# Home route
get("/") do
  erb("Welcome to Omnicalc 3")
end

# Umbrella route
get("/umbrella") do
  erb(:umbrella_form)
end

# Umbrella processing
post("/process_umbrella") do
  # Fetch location from params hash
  @user_location = params.fetch("user_loc")
  
  # Construct Google Maps' URL
  gmaps_url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{escape(@user_location)}&key=#{GMAPS_KEY}"

  # GET data from Google Maps API
  raw_location = JSON.parse(HTTP.get(gmaps_url))

  # Abort execution if Google Maps API does not find location
  return "Whoa! We don't know that place :( <a href='/umbrella'>Go back</a>!" if raw_location["results"].empty?

  # Get coordinates 
  @loc_hash = raw_location["results"][0]["geometry"]["location"]
  @latitude = @loc_hash.fetch("lat")
  @longitude = @loc_hash.fetch("lng")

  # Save coordinates to cookies hash for last location search
  cookies["last_location"] = @user_location
  cookies["last_lat"] = @latitude
  cookies["last_lng"] = @longitude

  # Construct Pirate Weather's URL
  p_weather_url = "https://api.pirateweather.net/forecast/#{PIRATE_WEATHER_KEY}/#{@latitude},#{@longitude}" 
  
  # Get forecast
  raw_forecast = JSON.parse(HTTP.get(p_weather_url))

  # Return message if Pirate Weather's API errors out
  if raw_forecast["error"]
    puts "Error: #{raw_forecast["error"]}"
    halt 400, erb("Error getting forecast :( <a href='/umbrella'>Go back</a>!")
  end

  # Get current weather
  @summary = raw_forecast["currently"]["summary"]
  @temperature = raw_forecast["currently"]["temperature"]


  # Check future precipitation probability
  data_12hr_window = raw_forecast["hourly"]["data"][1..12]
  future_precip = data_12hr_window.each{|hour| hour["hour"] = data_12hr_window.index(hour) + 1}
  future_precip.select!{|hour| hour["precipProbability"] >= 0.10}
  @advice = future_precip.empty? ? " You probably won't need an umbrella." : "You might want to take an umbrella!"
 
  # Render template
  erb(:umbrella_results)
end

# Message route
get("/message") do
  erb(:single_message_form)
end

# Handle requests to OpenAI's API
def query_gpt(messages)
  
  # Construct request headers
  request_headers_hash = {
    "Authorization" => "Bearer #{ENV.fetch("OPENAI_API_KEY")}",
    "content-type" => "application/json"
  }

  # Construct request body
  request_body_hash = {
    "model" => "gpt-3.5-turbo",
    "messages" => messages
  }

  # Convert body hash to JSON
  request_body_json = JSON.generate(request_body_hash)

  # Query API
  raw_response = HTTP.headers(request_headers_hash).post(
    "https://api.openai.com/v1/chat/completions",
    :body => request_body_json
  ).to_s

  # Parse response body into hash and return it
  parsed_response = JSON.parse(raw_response)
  
end

# Single-message processing
post("/process_single_message") do
  
  ## Get user's message from params hash
  @user_message = params["the_message"]

  ## Construct messages hash from user input
  request_body_messages = [
    {
      "role" => "system",
      "content" => "You are a helpful assistant who talks like Shakespeare."
    },
    {
      "role" => "user",
      "content" => @user_message
    }
  ]
  
  ## Query API
  parsed_response = query_gpt(request_body_messages)
  
  ## Get GPT's message from response
  @gpt_response = parsed_response.dig("choices", 0, "message", "content")
  
  erb(:single_message_results)
end

# Chat route
get("/chat") do
  erb(:chat)
end

# Chat processing
post("/add_message_to_chat") do

  ## Get user's message from params hash
  @user_message = params["user_message"]

  ## Construct message hash from user input
  user_message_hash =  {
    "role" => "user",
    "content" => @user_message
  }

  ## Retrieve chat history from cookies if present and append user's propmt
  @chat_history = cookies["chat_history"].empty? ? Array.new() : JSON.parse(cookies["chat_history"])
  @chat_history << user_message_hash
  
  ## Query API
  parsed_response = query_gpt(@chat_history)

  ## Get GPT's answer from response
  @gpt_response = parsed_response.dig("choices", 0, "message", "content")

  ## Construct message hash from GPT's answer
  gpt_response_hash =  {
    "role" => "assistant",
    "content" => @gpt_response
  }

  ## Append GPT's answer to chat history hash and store it in cookie
  @chat_history << gpt_response_hash
  cookies["chat_history"] = JSON.generate(@chat_history)

  ## Render template
  erb(:chat)
end

# Clear chat route
post("/clear_chat") do
  
  ## Clear chat history cookie 
  cookies["chat_history"] = nil

  ## Render template
  erb(:chat)
end
