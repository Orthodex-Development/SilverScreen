require 'json'
require 'sinatra'
require 'httparty'
require 'themoviedb-api'
require 'dotenv'
require 'mechanize'
require 'byebug'

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

      action = if text.include? "discover" then "discover" else "find" end

      movie_action(action, text)
    end
  else
    render 200
  end
end

def movie_action(action, text)
  case action
  when "find"
    movie_id = text.match(/(.)*movie: (.*)/i)[2]
    title = Tmdb::Movie.detail(movie_id).title

    response = HTTParty.get("http://api.nytimes.com/svc/movies/v2/reviews/search.json?api-key=#{ENV["NY_TIMES_API_KEY"]}&query=#{title}")

    if response.code == 200
      json = JSON.parse(response.body)
      if json["results"].empty?
        reply(@recipient, "Sorry, but I couldn't find any review for that movie.")
      else
        url = json["results"][0]["link"]["url"]
        # Scrape NY Times review site for review
        agent = Mechanize.new
        page = agent.get(url)
        review = page.search("p.story-body-text").text
        logger.info "REVIEW: #{review}"
        reply(@recipient, "Found your review at #{url}" )
      end
    else
      reply(@recipient, "Sorry, but an error ocurred")
    end
    # Send review to Python app
    # Send review to bot.
    # reply(@recipient, "Here is the review for your movie: #{review}")
  when "discover"
    movies = Tmdb::Discover.movie(:"primary_release_date.gte" => Date.today.prev_month.strftime , :"primary_release_date.lte" => Date.today.strftime, :sort_by => "popularity.desc", :page => 1)
    title_arr = []
    movie_id = []
    movie_titles = movies["results"].each do |movie|
      title_arr << movie["title"]
      movie_id << movie["id"]
    end
    reply(@recipient, "These are the current popular movies: #{title_arr.map.with_index{ |x,i| "(#{movie_id[i]}) " + x }.join(", ")}")
    reply(@recipient, "To find details about a movie: \"find movie: movie_id\"")
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

get '/' do
  erb :index
end
