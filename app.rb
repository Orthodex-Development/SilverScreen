require 'json'
require 'sinatra'
require 'httparty'

set :endpoint, "https://graph.facebook.com/v2.6/me/messages?access_token=#{ENV['PAGE_TOKEN']}"

get '/webhook' do
  if params['hub.verify_token'] == ENV['VERIFY_TOKEN']
    params['hub.challenge']
  else
    render text: 'invalid token', status: :forbidden
  end
end

post '/webhook' do
    payload = params[:webhook]
    entry = params[:webhook][:entry][0][:messaging][0]

    if entry.has_key?(:message)
      message = entry[:message]
      if message[:is_echo]
        # This is a message_echoes callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-echo
        Rails.logger.warn "---> This is a message_echoes callback (when the bot sends a reply back)"
      else
        Rails.logger.warn "---> This is a message callback (when the bot receives a message)"
        # This is a message_received callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-received
        recipient = entry[:sender][:id]
        text = message[:text]

        reply(recipient, "You said '#{text}'. Unfortunately I can't do any thing with that request")
      end
    # This is a message_received callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-received
    elsif entry.has_key?(:postback)
      Rails.logger.warn "---> This is a messaging_postbacks callback"
    # This is a message_optins callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-received
    elsif entry.has_key?(:optin)
      Rails.logger.warn "---> This is a messaging_optins callback"
    # This is an account_linking callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/account-linking
    elsif entry.has_key?(:account_linking)
      Rails.logger.warn "---> This is a account_linking callback"
    # This is a message_delivery callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-delivered
    elsif entry.has_key?(:delivery)
      Rails.logger.warn "---> This is a message_deliveries callback"
      # This is a message_read callback: https://developers.facebook.com/docs/messenger-platform/webhook-reference/message-read
    elsif entry.has_key?(:read)
      Rails.logger.warn "---> This is a message_read callback"
    end

    render text: 'received', status: :ok
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
