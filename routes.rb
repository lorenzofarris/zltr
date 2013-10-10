#require 'rubygems'
#require 'Haml'
require 'sinatra/base'
#require 'yaml'
require './cards'

class ZltApp <  Sinatra::Base
  set :logging,true
  set :sessions,true
  set :method_override, true
  set :inline_templates, true
  set :static, true
  
  before do
    $stderr.puts "path_info: #{request.path_info}"
    $stderr.puts "url: " + url("/")
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
    #inject_cedict_into_addcard((haml(:add)), params[:simplified])
    CardDB.render_cedict_choices(haml(:add), params)
  end
  
  post '/cs' do
    @line=CardDB.search_simplified(params[:simplified])
    @message=""
    #$stderr.puts "line is #{@line}"
    if @line.nil? || @line.length > 0
      @line={:simplified=>'', :pinyin=>'', :english=>''}
      @message="Character #{params[:simplified]} not found."
    end
    haml :cs
  end

  # list the flashcards
  get "/fc" do
    CardDB.list_all_cards(haml(:cards), url("/fc"))
  end
  
  post "/fc/add" do
    "adding flashcard"
    CardDB.add_flashcard(params)
    CardDB.list_all_cards(haml(:cards),url("/fc"))
  end

  get "/fc/edit/:id" do
    CardDB.edit_card(haml(:edit_card), params[:id])
  end
  
  post "/fc/update" do
    CardDB.update_card(params)
    CardDB.list_all_cards(haml(:cards),url("/fc"))
  end
  
  get "/fc/delete-confirm/:id" do
    $stderr.puts "id=#{params[:id]}"
    CardDB.delete_confirm(haml(:delete_confirm),params[:id])
  end
  
  get "/fc/delete/:id" do
    CardDB.delete_card(params[:id])
    CardDB.list_all_cards(haml(:cards),url("/fc"))
  end
  
  get "/fc/review" do
    CardDB.render_card_review_front(haml(:review))
  end
  
  get "/fc/check" do
    CardDB.render_card_review_full(haml(:review))
  end
   
  post "/fc/score" do
    redirect to('/fc/review') unless CardDB.review_cards_left?
    cards_left = CardDB.score_card(params[:score].to_i)
    if cards_left == 0
      haml :review_done
    else
      CardDB.render_card_review_front(haml(:review))
    end
  end
  
end
