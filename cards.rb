#!/usr/bin/ruby
require 'rubygems'
require 'sinatra'
require 'Haml'
require 'sequel'
require 'Nokogiri'

DB=Sequel.sqlite('resources/zltdb')
Sequel.datetime_class = DateTime

def search_simplified(simplified_character)
  #"your character is #{simplified_character}"
  entries=DB[:cedict]
  entries.first(:simplified=>simplified_character)
end

get '/hi' do
  "Hello, World!"
end

get '/' do
  haml :index
end

get '/add' do
  haml :add
end

post '/csa' do
  @doc = Nokogiri::HTML::DocumentFragment.parse(haml(:add))
  
  @doc.to_html
end

post '/cs' do
  @line=search_simplified(params[:simplified])
  haml :cs
end

