require 'json'
require 'sinatra'
require 'httparty'

set :endpoint, "https://graph.facebook.com/v2.6/me/messages?access_token=#{ENV['PAGE_TOKEN']}"

helpers do
  def logger
    request.logger
  end
end

get '/webhook' do
  if params['hub.verify_token'] == ENV['VERIFY_TOKEN']
    params['hub.challenge']
  else
    render text: 'invalid token', status: :forbidden
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
        # This is a message_echoes callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-echo
        logger.warn "---> This is a message_echoes callback (when the bot sends a reply back)"
      else
        logger.warn "---> This is a message callback (when the bot receives a message)"
        # This is a message_received callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-received
        recipient = entry["sender"]["id"]
        text = message["text"]

        reply(recipient, "You said '#{text}'. Unfortunately I can't do any thing with that request")
      end
    end

    render 200
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
