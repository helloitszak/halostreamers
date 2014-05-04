# encoding: UTF-8
CONFIG = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), 'config.yaml'))
TWITCH_URL = /http:\/\/www\.twitch\.tv\/(.+)\/profile/

class Streamers
  attr_reader :cache

  def initialize(cache)
    @cache = cache
  end

  def halo_streamers
    streamers = []

    doc = Nokogiri::HTML(open('http://haloruns.com/runners'))
    table = doc.css('#runnersTable')

    header_row = table.css('table tr th').to_a

    runner_index = header_row.index { |x| x.text == 'Runner' }
    points_index = header_row.index { |x| x.text == 'Overall' }
    twitch_index = header_row.index { |x| x.text == 'Twitch' }


    games = ['Halo CE', 'Halo 2', 'Halo 3', 'ODST', 'Reach', 'Halo 4']

    games.map! do |game|
      [game, header_row.index { |x| x.text == game }]
    end

    games = Hash[*games.flatten]

    table.css("tbody tr").each do |row|
      cols = row.css("td")
      if cols.empty?
        next
      end

      twitch_link = cols[twitch_index].css("a")
      if twitch_link.empty?
        next
      end

      streamer = {}
      streamer[:games] = games.select do |k,v|
        cols[v].content == '✓'
      end.map do |k,v|
        k
      end

      if twitch_link.first.attribute('href').value =~ TWITCH_URL
        streamer[:twitch] = $1
      end

      streamer[:runner] = cols[runner_index].content
      streamer[:points] = cols[points_index].content

      streamers << streamer
    end
    streamers
  end

  def cached_halo_runners
    @cache.fetch("halo_streamers") do
      halo = halo_streamers
      @cache.set("halo_streamers", halo, CONFIG["caching"]["halo"])
      halo
    end
  end

  def stream_info(users)
    http = Net::HTTP.new("api.twitch.tv", 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    if users.is_a? Array
      users = users.map { |s| s.strip.downcase }.join(",")
    else
      users = users.strip.downcase
    end

    request = Net::HTTP::Get.new("/kraken/streams?channel=#{users}")

    request.initialize_http_header({
      "Accept" => "application/vnd.twitchtv.v3+json",
      "Client-ID" => CONFIG["twitch_id"]
    })

    response = http.request(request)

    unless response.kind_of?(Net::HTTPSuccess)
      return []
    end

    rj = JSON.parse(response.body)

    rj["streams"]
  end

  class Webapp < Sinatra::Base
    set :cache, Dalli::Client.new(CONFIG["caching"]["server"], {:namespace => CONFIG["caching"]["namespace"]})
    set :streamers, Streamers.new(settings.cache)

    configure do
      settings.cache.flush
    end

    get '/' do
      erb :index
    end

    get '/streamer' do
      username = params['user']

      runners = settings.streamers.cached_halo_runners

      unless username
        return 'You need to specify a user.'
      end

      runner = runners.find do |r|
        [
          r[:runner].downcase,
          r[:twitch].downcase
        ].include?(username.downcase)
      end

      unless runner
        return 'User not found, dog.'
      end

      twitch_info = settings.streamers.stream_info(runner[:twitch]).first

      response = []
      response << "#{username} is http://twitch.tv/#{runner[:twitch]}."
      response << "Plays #{runner[:games].join(', ')}."
      response << "HaloRuns points #{runner[:points]}."

      if twitch_info
        response << "Currently streaming #{twitch_info['game']}"
      end
      return response.join(' ')
    end

    get '/streams' do
      streamlist = []

      if CONFIG["halo_streams"]
        runners = settings.streamers.cached_halo_runners
        runner_twitches = runners.map { |x| x[:twitch] }
        streamlist.push(*runner_twitches)
      end

      # Add additional streamers here (shameless self plug)
      streamlist.push(*CONFIG["additional_streams"])

      # Grab Twitch Information for
      streamers ||= settings.cache.fetch("stream_status") do
        list = streamlist.each_slice(20).map { |s| settings.streamers.stream_info(s) }.flatten
        settings.cache.set("stream_status", list, CONFIG["caching"]["twitch"])
        list
      end

      # Default top X Users to return
      top = streamers.length

      # Parameters
      if params['top']
        top = params['top'].to_i
      end

      if params['sort'] == 'desc'
        # highest to lowest
        streamers.sort! { |x,y| y["viewers"] <=> x["viewers"] }
      else
        # lowest to highest
        streamers.sort! { |x,y| x["viewers"] <=> y["viewers"] }
      end


      filter = (params['filter'] or 'halo')
      if filter and not params['nofilter']
        streamers.select! { |s| s["channel"]["game"].downcase.include?(filter) }
      end

      #stream["channel"]["display_name"], :viewers => stream["viewers"]}

      streamers[0, top].each_with_index.map do |stream, index|
        tag = stream["channel"]["game"]
        if params['viewers']
          tag += ", Viewers: #{stream["viewers"]}"
        end

        "#{index+1}: #{stream["channel"]["display_name"]} (#{tag})"
      end.join(", ")
    end

    get '/application.css' do
      scss :application
    end
  end
end


