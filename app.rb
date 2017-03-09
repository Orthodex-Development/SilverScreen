require 'json'
require 'sinatra'
require 'httparty'
require 'themoviedb-api'
require 'redis'
#require 'byebug'
require 'dotenv'
require 'mechanize'

configure do
  REDIS = Redis.new(url: ENV["REDISCLOUD_URL"] || 'redis://localhost:6379/15')
  FACEBOOK_URL = "https://graph.facebook.com/v2.6/me/messages?access_token=#{ENV["PAGE_TOKEN"]}"
  if ENV['RACK_ENV'].nil? || ENV['RACK_ENV'] == "development"
    DOMAIN = "http://localhost:3000"
  else
    DOMAIN = "https://minerva-project.herokuapp.com"
  end
  Dotenv.load
end

before do
  Tmdb::Api.key(ENV["TMDB_API_KEY"])
end

helpers do
  def logger
    request.logger
  end
end

post '/analysis' do
  request.body.rewind  # in case someone already read it
  data = JSON.parse request.body.read
  reply(data["user"], data["message"])
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
      200
    end
  else
    200
  end
end

def movie_action(action, text)
  case action
  when "find"
    movie_id = text.match(/(.)*movie: (.*)/i)[2]
    review_url = REDIS.get "url_#{movie_id}"
    if review_url.nil?
      logger.info "Movie not stored. Fetching data from NY Times api."
      fetch_review(movie_id)
    else
      logger.info "Review found in Redis."
      reply(@recipient, "Found your review at #{review_url}. Crunching numbers to give you the best aspects of the movie.." )
      # Send this review to Feature Extraction and Opinion Mining Module (Minerva) : https://github.com/Orthodex-Development/Minerva
      review = REDIS.get "wh_#{movie_id}"
      send_review_to_minerva(review, movie_id, @recipient)
    end
  when "discover"
    movies = Tmdb::Discover.movie(:"primary_release_date.gte" => Date.today.prev_month.strftime , :"primary_release_date.lte" => Date.today.strftime, :sort_by => "popularity.desc", :page => 1)
    title_arr = []
    movie_id = []
    movie_titles = movies["results"].each do |movie|
      title_arr << movie["title"]
      movie_id << movie["id"]
    end
    reply(@recipient, "These are the current popular movies: #{title_arr.map.with_index{ |x,i| "(#{movie_id[i]}) " + x }.join(", ")} \n To find details about a movie type - find movie: movie_id")
    #reply(@recipient, "To find details about a movie type - find movie: movie_id")
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
  logger.info "send to Facebook, body: #{body}"
  HTTParty.post(FACEBOOK_URL, body: body)
end

def fetch_review(movie_id)
  title = Tmdb::Movie.detail(movie_id).title

  response = HTTParty.get("http://api.nytimes.com/svc/movies/v2/reviews/search.json?api-key=#{ENV["NY_TIMES_API_KEY"]}&query=#{title}")
  reply(@recipient, "Got the movie! Retrieving reviews...")

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
      # logger.info "REVIEW: #{review}"
      logger.info "Storing Review in REDIS. Review size: #{review.size}"
      REDIS.setnx "wh_#{movie_id}", review
      REDIS.setnx "url_#{movie_id}", url
      # Send this review to Feature Extraction and Opinion Mining Module (Minerva) : https://github.com/Orthodex-Development/Minerva
      send_review_to_minerva(review, movie_id, @recipient)
      # Send review link to bot.
      reply(@recipient, "Found your review at #{url}. Crunching numbers to give you the best aspects of the movie.." )
    end
  else
    reply(@recipient, "Sorry, but an error ocurred")
  end
end

def send_review_to_minerva(review, movie_id, user_id)
  HTTParty.post(DOMAIN + "/api/tokenize",
    body:
      {
        :token => {
          :review => review,
          :movie_id => movie_id,
          :user_id => user_id
        }
      })
end

get '/' do
  erb :index
end
