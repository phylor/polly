require 'telegram/bot'
require 'securerandom'

require 'byebug'

token = ENV['TELEGRAM_BOT_TOKEN']

polls = {}

def get_chat_id(message)
  case message
  when Telegram::Bot::Types::CallbackQuery
    message.message.chat.id
  when Telegram::Bot::Types::Message
    message.chat.id
  end
end

def add_votee(message, poll)
  option_id = message.data.split('_')[1]

  poll[:options].map do |option|
    if option[:id] == option_id
      # TODO: users should not be able to vote twice for the same option
      option[:votees] << message.from
      option
    else
      option
    end
  end
end

def send_statistics(bot, chat_id, poll)
  statistics = poll[:options].map do |option|
    "#{option[:text]} (#{option[:votees].map(&:first_name).join(', ')})"
  end.join(' / ')

  bot.api.send_message(chat_id: chat_id, text: "#{poll[:title]}: #{statistics}")
end

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    chat_id = get_chat_id(message)
    poll = polls[chat_id]

    case message
    when Telegram::Bot::Types::CallbackQuery
      if poll.nil?
        puts "Don't know the poll for chat id #{chat_id}"
        next
      end

      if message.data.start_with?('option')
        poll[:options] = add_votee(message, poll)

        send_statistics(bot, chat_id, poll)
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
