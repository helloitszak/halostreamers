CONFIG = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), 'config.yaml'))

class Streamers
	def self.halo_streamers
		streamers = []

		doc = Nokogiri::HTML(open("http://haloruns.com/runners"))
		table = doc.css("#runnersTable")

		twitch_index = table.css("tbody tr th").to_a.index { |x| x.text == "Twitch" }
		table.css("tbody tr").each do |row|
			cols = row.css("td")
			if cols.empty?
				next
			end
			
			twitch_link = cols[twitch_index].css("a")

			if not twitch_link.empty?
				streamers << twitch_link.first.attribute("href").value
			end
		end

		streamers.map { |x| x =~ /http:\/\/www\.twitch\.tv\/(.+)\/profile/; $1 }
	end

	def self.stream_info(users)
		# puts "DEBUG: Info for #{users.join(", ")}"
		http = Net::HTTP.new("api.twitch.tv", 443)
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE

		if users.is_a? Array
			users = users.map(&:downcase).join(",")
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
		
		get '/' do
			erb :index
		end
		
		get '/streams' do
			streamlist = []

			if CONFIG["halo_streams"]
				# Halo Streamers
				halo_streamers ||= settings.cache.fetch("halo_streamers") do
					halo = Streamers.halo_streamers
					settings.cache.set("halo_streamers", halo, CONFIG["caching"]["halo"])
					halo
				end
				streamlist.push(*halo_streamers)
			end

			# Add additional streamers here (shameless self plug)
			streamlist.push(*CONFIG["additional_streams"])

			# Grab Twitch Information for 
			streamers ||= settings.cache.fetch("stream_status") do
				list = streamlist.each_slice(20).map { |s| Streamers.stream_info(s) }.flatten
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


