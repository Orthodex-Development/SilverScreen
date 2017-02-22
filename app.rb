require 'json'
require 'sinatra'
require 'httparty'
require 'themoviedb-api'
require 'dotenv'

set :endpoint, "https://graph.facebook.com/v2.6/me/messages?access_token=#{ENV['PAGE_TOKEN']}"

before do
  Dotenv.load
  Tmdb::Api.key(ENV["TMDB_API_KEY"])
  logger.info "key? : #{ENV.key?("TMDB_API_KEY")}"
end

helpers do
  def logger
    request.logger
  end
end

get '/webhook' do
  if params['hub.verify_token'] == ENV['VERIFY_TOKEN']
    params['hub.challenge']
  else
    render 403
  end
end

post '/webhook' do
  request.body.rewind  # in case someone already read it
  data = JSON.parse request.body.read
  logger.info "Payload: #{data.inspect}"
  entry = data["entry"][0]["messaging"][0]

  if entry.has_key?("message")
    message = entry["message"]
    if message["is_echo"]
      logger.info "---> This is a message_echoes callback (when the bot sends a reply back)"
    else
      logger.info "---> This is a message callback (when the bot receives a message)"
      @recipient = entry["sender"]["id"]
      text = message["text"]

      action = "discover"

      movie_action(action, text)

      reply(@recipient, "You said '#{text}'. Unfortunately I can't do any thing with that request")
    end
  else
    render 200
  end
end

def movie_action(action, text)
  case action
  when "find"
    movie = text.match(/(.)*movie: (.*)/i)[2]
    response = JSON.parse(Tmdb::Search.movie(movie, page: 1))
    movie_id = response["results"][0]["id"]
    json = JSON.parse(Tmdb::Movie.reviews(movie_id))
    review = json["content"]

    # Send review to Python app
    # Send review to bot.
    reply(@recipient, "Here is the review for your movie: #{review}")
  when "discover"
    movies = Tmdb::Discover.movie(:"primary_release_date.gte" => Date.today.prev_month.strftime , :"primary_release_date.lte" => Date.today.strftime, :sort_by => "popularity.desc", :page => 1)
    title_arr = []
    movie_id = []
    movie_titles = movies["results"].each do |movie|
      title_arr << movie["title"]
      movie_id << movie["id"]
    end
    reply(@recipient, "These are the current popular movies: #{title_arr.map.with_index{ |x,i| "(#{movie_id[i]}) " + x }.join(", ")}")
    reply(@recipient, "To find details about a movie: \"find movie_id\"")
  end
end

def reply(sender, text)
  body = {
    recipient: {
      id: sender
    },
    message: {
      text: text
    }
  }
  logger.info "send to #{settings.endpoint}, body: #{body}"
  #HTTParty.post(settings.endpoint, body: body)
end

def greetings(sender, text)
  HTTParty.post(settings.endpoint, body: body)
  reply(sender, 'Hi! I am movie bot! I recommend current movies to you!')
end
