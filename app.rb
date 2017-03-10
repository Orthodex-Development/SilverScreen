require 'json'
require 'sinatra'
require 'httparty'
require 'themoviedb-api'
require 'redis'
require 'will_paginate/array'
#require 'byebug'
require 'dotenv'
require 'mechanize'

configure do
  Dotenv.load
  REDIS = Redis.new(url: ENV["REDISCLOUD_URL"] || 'redis://localhost:6379/15')
  FACEBOOK_URL = "https://graph.facebook.com/v2.6/me/messages?access_token=#{ENV["PAGE_TOKEN"]}"
  IMAGE_PATH = "https://image.tmdb.org/t/p/w500"
  if ENV['RACK_ENV'].nil? || ENV['RACK_ENV'] == "development"
    DOMAIN = "http://localhost:3000"
  else
    DOMAIN = "https://minerva-project.herokuapp.com"
  end
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
  200
end

get '/webhook' do
  if params['hub.verify_token'] == ENV['VERIFY_TOKEN']
    params['hub.challenge']
  else
    403
  end
end

post '/webhook' do
  request.body.rewind  # in case someone already read it
  data = JSON.parse request.body.read
  logger.info "Payload: #{data.inspect}"
  entry = data["entry"][0]["messaging"][0]

  if !entry["postback"].nil?
    # Postback
    sender = entry["sender"]["id"]
    @recipient  = sender
    payload = JSON.parse(entry["postback"]["payload"])
    if payload.has_key?("action")
      @movies = get_movies
      reply_with_list(true, payload["page"])
    elsif payload.has_key?("movie_id")
      movie_action("find", payload["movie_id"])
    end
    200
  else
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
end

def get_movies
  Tmdb::Discover.movie(:"primary_release_date.gte" => Date.today.prev_month.strftime , :"primary_release_date.lte" => Date.today.strftime, :sort_by => "popularity.desc", :page => 1)
end

def movie_action(action, m_id)
  case action
  when "find"
    movie_id = m_id
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
    @movies = get_movies
    reply_with_list
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
  logger.info "send to #{FACEBOOK_URL}, body: #{body}"
  HTTParty.post(FACEBOOK_URL, body: body)
end

def reply_with_list(more = false, page = 0)

  elements = []

  logger.info "page: #{page + 1}"
  @movies["results"].paginate(:page => page + 1, :per_page => 4).each do |movie|
  elements << {
            "title": movie["title"],
            "image_url": IMAGE_PATH + movie["poster_path"],
            "subtitle": Date.parse(movie["release_date"]).strftime("%d %b, %Y"),
            "buttons": [
                {
                  "title": "Get Ratings",
                  "type": "postback",
                  "payload": {"movie_id": movie["id"]}.to_json
                }
              ]
            }
  end

  body = {
    "recipient":{
        "id": @recipient
      },
    "message": {
      "attachment": {
        "type": "template",
        "payload": {
          "template_type": "list",
          "top_element_style": "compact",
          "elements": elements,
          "buttons": [
            {
              "title": "View More",
              "type": "postback",
              "payload": {"action": "more", "page": page + 1}.to_json
            }
          ]
        }
      }
    }
  }

  logger.info "send to #{FACEBOOK_URL}, body: #{body.to_json}"
  response = HTTParty.post(FACEBOOK_URL, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  puts "#{response.message}, #{response.code}, #{response.parsed_response}"
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
