require "sinatra"
require "sinatra/reloader"
require "http"
require "sinatra/cookies"
include ERB::Util

GMAPS_KEY = ENV.fetch("GMAPS_KEY")
PIRATE_WEATHER_KEY = ENV.fetch("PIRATE_WEATHER_KEY")
get("/") do
  erb("Welcome to Omnicalc 3")
end

get("/umbrella") do
  erb(:umbrella_form)
end

post("/process_umbrella") do
  @user_location = params.fetch("user_loc")
  # Construct Google Maps' URL
  gmaps_url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{url_encode(@user_location)}&key=#{GMAPS_KEY}"

  # GET data from Google Maps API
  raw_location = JSON.parse(HTTP.get(gmaps_url))

  # Abort execution if Google Maps API returns no results
  return "Whoa! We don't know that place :( <a href='/umbrella'>Go back</a>!" if raw_location["results"].empty?

  # Get coordinates 
  @loc_hash = raw_location["results"][0]["geometry"]["location"]
  @latitude = @loc_hash.fetch("lat")
  @longitude = @loc_hash.fetch("lng")

  cookies["last_location"] = @user_location
  cookies["last_lat"] = @latitude
  cookies["last_lng"] = @longitude

  # Construct Pirate Weather's URL
  p_weather_url = "https://api.pirateweather.net/forecast/#{PIRATE_WEATHER_KEY}/#{@latitude},#{@longitude}" 
  
  # Get forecast
  raw_forecast = JSON.parse(HTTP.get(p_weather_url))

  if raw_forecast["error"]
    puts "Error: #{raw_forecast["error"]}"
    halt 400, erb("Error getting forecast :( <a href='/umbrella'>Go back</a>!")
  end

  @summary = raw_forecast["currently"]["summary"]
  @temperature = raw_forecast["currently"]["temperature"]


  # Check future precipitation probability
  data_12hr_window = raw_forecast["hourly"]["data"][1..12]
  future_precip = data_12hr_window.each{|hour| hour["hour"] = data_12hr_window.index(hour) + 1}
  future_precip.select!{|hour| hour["precipProbability"] >= 0.10}
  @advice = future_precip.empty? ? " You probably won't need an umbrella." : "You might want to take an umbrella!"
 
  erb(:umbrella_results)
end

get("/message") do
  
end
