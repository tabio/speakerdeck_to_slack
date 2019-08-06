require 'feedjira'
require 'httparty'
require 'pry'
require 'slack-notifier'

class Response
  attr_accessor :id, :title, :content, :url, :published, :tags

  TAGS = %w|rails ruby mysql apache nginx elasticsearch|

  def initialize(entry)
    @id        = entry.id
    @title     = entry.title
    @content   = entry.content.scan(/<p>(.*?)<\/p>/).join("\n")
    @url       = entry.url
    @published = entry.published.getlocal
    set_tags
  end

  def no_tag?
    tags.empty?
  end

  private

  # title, contentから正規表現を利用しタグを付与
  def set_tags
    @tags = []
    TAGS.each do |tag|
      reg =  /#{tag}/i
      @tags << tag if content.match?(reg) || title.match?(reg)
    end
  end
end

class Request
  SLEEP_COUNT = 60
  PAGE_NUM    = 5

  class << self
    def get_feed
      urls = %w|
        https://speakerdeck.com/c/programming.atom?page=%s
        https://speakerdeck.com/c/technology.atom?page=%s
      |

      responses = []
      urls.each do |url|
        # FIXME: 前回取得したところまで遡るようにしたい。一旦5ページとしクローリング頻度で調整
        1.step(PAGE_NUM) do |page_num|
          xml = HTTParty.get(url % page_num).body
          feed = Feedjira.parse(xml)

          feed.entries.each do |entry|
            responses << Response.new(entry)
          end

          sleep SLEEP_COUNT
        end
      end

      # タグなし、掲載日が昨日のデータ以外は除外
      responses.reject! { |res| res.no_tag? || res.published.to_date != (DateTime.now - 1).to_date }
    end
  end
end

WEBHOOK_URL = ''
API_KEY     = ''
SECRET_KEY  = ''

responses = Request.get_feed

notifier = Slack::Notifier.new WEBHOOK_URL

responses.each do |obj|
  message << []
  message << '-' * 30
  message << "*#{obj.title}*"
  message << obj.content
  message << obj.url

  obj.tags.each do |tag|
    notifier.ping message.join("\n"), channel: "##{tag}" unless message.empty?
  end
end
