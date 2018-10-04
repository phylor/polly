require 'telegram/bot'
require 'securerandom'

require 'byebug'

token = ENV['TELEGRAM_BOT_TOKEN']

polls = {}

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    poll = if message.respond_to?(:chat)
             polls[message.chat.id]
           else
             polls[message.message.chat.id]
           end

    case message
    when Telegram::Bot::Types::CallbackQuery
      if poll.nil?
        puts "Don't know the poll for chat id #{message.message.chat.id}"
        next
      end

      if message.data.start_with?('option')
        option_id = message.data.split('_')[1]

        poll[:options] = poll[:options].map do |option|
          if option[:id] == option_id
            # TODO: users should not be able to vote twice for the same option
            option[:votees] << message.from
            option
          else
            option
          end
        end

        statistics = poll[:options].map do |option|
          "#{option[:text]} (#{option[:votees].map(&:first_name).join(', ')})"
        end.join(' / ')
        bot.api.send_message(chat_id: message.from.id, text: "#{poll[:title]}: #{statistics}")
      end
    when Telegram::Bot::Types::Message
      if poll.nil?
        case message.text
        when '/start'
          bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}")
        when '/stop'
          bot.api.send_message(chat_id: message.chat.id, text: "Bye, #{message.from.first_name}")
        when '/newpoll'
          bot.api.send_message(chat_id: message.chat.id, text: "Nice. What's the title of your poll?")

          polls[message.chat.id] = { state: :poll_title }
        end
      else
        case message.text
        when '/finish'
          bot.api.send_message(chat_id: message.chat.id, text: 'Alright.')

          kb = poll[:options].map do |option|
            Telegram::Bot::Types::InlineKeyboardButton.new(text: option[:text], callback_data: "option_#{option[:id]}")
          end

          markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
          bot.api.send_message(chat_id: message.chat.id, text: poll[:title], reply_markup: markup)
        else
          case poll[:state]
          when :poll_title
            poll[:title] = message.text

            bot.api.send_message(chat_id: message.chat.id, text: "I created a poll with the title \"#{poll[:title]}\". What's your first option? You need at least two.")

            poll[:state] = :poll_options
          when :poll_options
            poll[:options] = [] if poll[:options].nil?
            poll[:options] << { id: SecureRandom.hex, text: message.text, votees: [] }

            bot.api.send_message(chat_id: message.chat.id, text: "Added option. What's your next option? Use `/finish` to end setting up the poll.")
          end
        end
      end
    end

    puts message.inspect
  end
end
