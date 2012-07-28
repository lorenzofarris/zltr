#require 'rubygems'
#require 'Haml'
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
    session.delete(:deck)
    list_all_cards(haml(:cards))
  end

  get "/fc/edit/:id" do
    edit_card(haml(:edit_card), params[:id])
  end
  
  post "/fc/update" do
    update_card(params)
    session.delete(:deck)
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
  
  get "/fc/review" do
    # get a review deck, if I haven't got one
    unless session.key?(:deck) 
      deck=Deck.new(20)
      session[:deck]=deck.to_json
    else
      deck=Deck.json_create(session[:deck])
    end
    card=deck.current_card
    render_card_review_front(card,haml(:review))
  end
  
  get "/fc/check" do
    unless session.key?(:deck) && session[:deck].length > 0
      redirect to('/fc/review')
    end
    deck=Deck.json_create(session[:deck])
    card=deck.current_card
    render_card_review_full(card,haml(:review))
  end
   
  post "/fc/score" do
    unless session.key?(:deck) && session[:deck].length > 0
      redirect to('/fc/review')
    end
    deck=Deck.json_create(session[:deck])
    card=deck.current_card
    score = params[:score].to_i
    if score < 4
      deck.repeat_card
    else
      record_score(score, card)
      deck.return_card_to_box
      session[:deck]=deck.to_json()
    end
    if deck.length == 0
      haml :review_done
    else
      card=deck.current_card
      render_card_review_full(card,haml(:review))
    end
  end
  
end
