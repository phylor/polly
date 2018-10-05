require 'telegram/bot'
require 'securerandom'

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
      if option[:votees].map { |o| o[:user_id] }.include?(message.from.id)
        option[:votees].delete_if { |vote| vote[:user_id] == message.from.id }
        yield option, :removed
      else
        option[:votees] << { user_id: message.from.id, user: message.from }
        yield option, :added
      end

      option
    else
      option
    end
  end
end

def send_statistics(bot, chat_id, poll)
  options = poll[:options].map do |option|
    <<~OPTION
      #{option[:text]}
      #{option[:votees].map do |user|
        "☝ #{user[:user].first_name} #{user[:user].last_name}"
      end.join("\n")}
    OPTION
  end.join("\n\n")

  statistics = <<~STATISTICS
               *#{poll[:title]}*

               #{options}
               STATISTICS

  bot.api.send_message(chat_id: chat_id, text: statistics, parse_mode: :markdown)
end

def show_poll(bot, chat_id, poll)
  kb = poll[:options].map do |option|
    Telegram::Bot::Types::InlineKeyboardButton.new(text: option[:text], callback_data: "option_#{option[:id]}")
  end

  markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
  bot.api.send_message(chat_id: chat_id, text: poll[:title], reply_markup: markup)
end

def finish_poll(bot, chat_id, poll)
  poll[:state] = :voting
  poll[:options] = [] if !poll.has_key?(:options)

  bot.api.send_message(chat_id: chat_id, text: 'Alright.')
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
        poll[:options] = add_votee(message, poll) do |option, type|
          case type
          when :added
            bot.api.send_message(chat_id: chat_id, text: "#{message.from.first_name} voted for *#{option[:text]}*.", parse_mode: :markdown)
          when :removed
            bot.api.send_message(chat_id: chat_id, text: "#{message.from.first_name} withdrew the vote for *#{option[:text]}*.", parse_mode: :markdown)
          end
        end
      elsif message.data == 'finish'
        finish_poll(bot, chat_id, poll)
        show_poll(bot, chat_id, poll)
      end
    when Telegram::Bot::Types::Message
      case message.text
        when /\/newpoll.*/
          title = message.text.gsub(/\/newpoll\s*/, '')
          polls[message.chat.id] = { state: :poll_title, title: title }

          bot.api.send_message(chat_id: message.chat.id, text: "I created a poll with the title *#{title}*. What's your first option? You need at least two.", parse_mode: :markdown)
      end

      if !poll.nil?
        case message.text
        when '/finish'
          finish_poll(bot, chat_id, poll)
          show_poll(bot, chat_id, poll)
        when /\/option.*/
          option = message.text.gsub(/\/option\s*/, '')

          poll[:options] = [] if poll[:options].nil?
          poll[:options] << { id: SecureRandom.hex, text: option, votees: [] }

          keyboard = [Telegram::Bot::Types::InlineKeyboardButton.new(text: 'Finish poll', callback_data: 'finish')]
          markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)

          bot.api.send_message(chat_id: message.chat.id, text: "Added option. What's your next option? Use `/finish` to end setting up the poll.", reply_markup: markup)
        when '/showpoll'
          show_poll(bot, chat_id, poll)
        when '/showstats'
          send_statistics(bot, chat_id, poll)
        end
      end
    end

    puts message.inspect
  end
end
