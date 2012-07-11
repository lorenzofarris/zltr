#require 'rubygems'
require 'Haml'
require 'sinatra/base'
require 'cards'

class ZltApp <  Sinatra::Base
  set :logging,true
  set :sessions,true
  set :method_override, true
  set :inline_templates, true
  set :static, true
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
    inject_cedict_into_addcard((haml(:add)), params[:simplified])
  end
  
  post '/cs' do
    @line=search_simplified(params[:simplified])
    haml :cs
  end
  # list the flashcards
  get "/fc" do
    list_all_cards(haml(:cards))
  end
  
  post "/fc/add" do
    "adding flashcard"
    add_flashcard(params)
    list_all_cards(haml(:cards))
  end

  get "/fc/edit/:id" do
    edit_card(haml(:edit_card), params[:id])
  end
  
  post "/fc/update" do
    update_card(params)
    list_all_cards(haml(:cards))
  end
  
  get "/fc/delete-confirm/:id" do
    $stderr.puts "id=#{params[:id]}"
    delete_confirm(haml(:delete_confirm),params[:id])
  end
  
  get "/fc/delete/:id" do
    delete_card(params[:id])
    list_all_cards(haml(:cards))
  end
end
