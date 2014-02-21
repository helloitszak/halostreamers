require 'rubygems'
require 'bundler'

Bundler.require

require 'net/http'
require 'open-uri'
require 'json'
require 'yaml'

require './streamers.rb'

run Streamers::Webapp