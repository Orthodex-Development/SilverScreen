require 'json'
require 'sinatra'
require "sinatra/namespace"
require 'httparty'

set :endpoint, "https://graph.facebook.com/v2.6/me/messages?access_token=#{ENV['PAGE_TOKEN']}"

namespace '/webhook' do
  get '/' do
    if params['hub.verify_token'] == ENV['VERIFY_TOKEN']
      render text: params['hub.challenge'], status: :ok
    else
      render text: 'invalid token', status: :forbidden
    end
  end

  post '/' do
      puts request.body
    begin
      request.body.rewind
      body = JSON.parse(request.body.read)

      entries = body[:entry]
      puts "Entries: #{entries}"

      entries.each do |entry|
        entry['messaging'].each do |message|
          text   = message[:message][:text].to_s
          sender = message[:sender][:id]

          if text.match(/hello/i)
            greetings(sender, 'Hello from the other side!')
          end

          if text.match(/bye/i)
            reply(sender, 'See you later dude')
          end

        end
      end
    rescue Exception => e
      puts e.message
    end

    status 200
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

  HTTParty.post(settings.endpoint, body: body)
end

def greetings(sender, text)
  HTTParty.post(settings.endpoint, body: body)
  reply(sender, 'Hi! I am movie bot! I recommend current movies to you!')
end
