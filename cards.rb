#!/usr/bin/ruby

require 'sequel'
require 'Nokogiri'
require 'json'
require 'date'

DB=Sequel.sqlite('resources/zltdb')
Sequel.datetime_class = DateTime

class Deck
  
  #until I better understand object initialization...
  # if deck is non-nil, I will populate from the argument
  # otherwise i will get a new deck from the db
  # this allows me to use serialized decks
  def initialize(num_cards=20, deck=nil)
    unless deck.nil?()
      @deck=deck
    else
      @deck=get_cards_due(num_cards)
    end
  end
  
  def to_json
    {
      "json_class" => self.class().name,
      "data" => {"deck" => @deck}
    }
  end
  def self.json_create(o)
    new(0,o['data']['deck'])
  end
  
  def current_card
    return nil if @deck.length == 0
    @deck[0]
  end
  
  def length
    return @deck.length
  end 

  def repeat_card
    # move the card from the top to the bottom of the deck
    card = @deck.shift
    @deck << card
  end


  def return_card_to_box
    @deck.shift
  end

end 

def record_score(score, wrapped_card)
  card = wrapped_card[:card]
  # calculate ease-factor
  new_ef(score, wrapped_card)
  # calculate next interval
  new_interval(wrapped_card)
  # update db with new ease-factor and next due date
  cards=DB[:cards].where(:id=>card[:id])
  cards.update(card)
  # record the attempt
  tries=DB[:card_tries]
  side=1  
  if wrapped_card[:type] == :english
    side=2
  end
  tries.insert(:date=>DateTime.now,
               :card=>card[:id],
               :side=>side,
               :q => score)
end

def new_interval(wrapped_card)
  # assume ease factor has already been updated
  # update the repetition interval in days for the card
  # which is needed for calculations, and
  # the next due date for review of the card
  card = wrapped_card[:card]
  if wrapped_card[:type] == :chinese
    old_interval = card[:chinese_interval]
    ef = card[:chinese_ef]
    new_interval = (old_interval * ef).round
    card[:chinese_interval]= new_interval
    card[:chinese_due]= card[:chinese_due]+new_interval
  else
    old_interval = card[:english_interval]
    ef = card[:english_ef]
    new_interval = (old_interval * ef).round
    card[:english_interval]= new_interval
    card[:english_due]= card[:english_due]+new_interval
  end
end   

def new_ef(score, wrapped_card)
  # calculated values from supermemo2 algorithm
  # score should be from 1 to 5
  return nil unless (1 <= score) && (score <= 5)
  ef_adder = [-1, -0.54, -0.32, -0.14, 0, 0.1]
  card = wrapped_card[:card]
  old_ef = 0
  if wrapped_card[:type] == :chinese
    old_ef=card[:chinese_ef]
    new_ef = old_ef + ef_adder[score]
    card[:chinese_ef] = new_ef < 1.3 ? 1.3 : new_ef
  else
    old_ef=card[:english_ef]
    new_ef = old_ef + ef_adder[score]
    card[:english_ef] = new_ef < 1.3 ? 1.3 : new_ef
  end
end

def get_cards_due(number=20)    
  #@deck=DB[:cards].filter{(english_due < DateTime.now) | (chinese_due < DateTime.now)}.all
  # I want to be able to grab both sides being due for review
  deck1=DB[:cards].order(:chinese_due).reverse.limit(number)
  deck2=DB[:cards].order(:english_due).reverse.limit(number)
  deck3 = []
  deck1.each do |card|
    deck3 << {:date_due=>card[:chinese_due], :type=>:chinese, :card=>card} 
  end
  deck2.each do |card|
    deck3 << {:date_due=>card[:english_due], :type=>:english, :card=>card}
  end
  deck3.sort! do |a,b| 
    case
    when a[:date_due]>b[:date_due]
      1
    when a[:date_due]<b[:date_due]
      -1
    else
      0
    end
  end 
  deck3[0..(number-1)]
end
  
def search_simplified(simplified_character)
  #"your character is #{simplified_character}"
  entries=DB[:cedict]
  entries.first(:simplified=>simplified_character)
end

# TODO: test out writing date to an in memory database in the irb
def add_flashcard(mapp)
  cards=DB[:cards]
  cards.insert(:traditional=>mapp['traditional'],
               :simplified=>mapp['simplified'],
               :pinyin=>mapp['pinyin'],
               :english=>mapp['english'],
               :english_due=>DateTime.now,
               :chinese_due=>DateTime.now,
               :english_ef=> 2.5,
               :chinese_ef=> 2.5,
               :english_interval=>1,
               :chinese_interval=>1)              
end

def render_card_review_front(wrapped_card,html)

  card=wrapped_card[:card]
  doc = Nokogiri::HTML::Document.parse(html)
  front=doc.at_css("#front")
  if card[:type]==:chinese
    front_visible=front.at_css(".character")
    front_visible.delete('hidden') if front_visible.key?('hidden')
    front_visible.content=card[:simplified]
  else
    front_visible=front.at_css(".english")
    front_visible.delete('hidden') if front_visible.key?('hidden')
    front_visible.content=card[:english]
  end
  check_form=doc.at_css("#check")
  check_form.delete('hidden') if check_form.key?('hidden')
  doc.to_html
end

def render_card_review_full(wrapped_card,html)
  card=wrapped_card[:card]
  doc = Nokogiri::HTML::Document.parse(html)
  front=doc.at_css("#front")
  back=doc.at_css("#back")
  if card[:type]==:chinese
    front_visible=front.at_css(".character")
    front_visible.delete('hidden') if front_visible.key?('hidden')
    front_visible.content=card[:simplified]
    back_pinyin=back.at_css(".pinyin")
    back_pinyin.delete('hidden') if back_pinyin.key?('hidden')
    back_pinyin.content=card[:pinyin]
    back_english=back.at_css(".english")
    back_english.delete('hidden') if back_english.key?('hidden')
    back_english.content=card[:english]
  else
    front_visible=front.at_css(".english")
    front_visible.delete('hidden') if front_visible.key?('hidden')
    front_visible.content=card[:english]
    back_pinyin=back.at_css(".pinyin")
    back_pinyin.delete('hidden') if back_pinyin.key?('hidden')
    back_pinyin.content=card[:pinyin]
    back_character=back.at_css(".character")
    back_character.delete('hidden') if back_character.key?('hidden')
    back_character.content=card[:simplified]
  end
  check_form=doc.at_css("#score")
  check_form.delete('hidden') if check_form.key?('hidden')
  doc.to_html
end


def list_all_cards(html_doc)
  #$stderr.puts(html_doc)
  doc = Nokogiri::XML::Document.parse(html_doc)
  cards_ds=DB[:cards]
  cards = cards_ds.all
  current_row = doc.at_css("tr.card_row")
  last_row=current_row
  first_row_flag=true
  cards.each  do |card|
    # already have first row in the template for layout purposes
    unless first_row_flag
      current_row=last_row.dup
      last_row.add_previous_sibling(current_row)
    else
      first_row_flag=false
    end
    current_row.at_css("td.simplified").content=card[:simplified]
    current_row.at_css("td.traditional").content=card[:traditional]
    current_row.at_css("td.pinyin").content=card[:pinyin]
    current_row.at_css("td.english").content=card[:english]
    a1 = current_row.at_css("td.index a")
    a1['href']="/fc/edit/#{card[:id]}"
    a1.content="Edit"
    a2 = current_row.at_css("td.delete a")
    a2['href']="/fc/delete-confirm/#{card[:id]}"
    a2.content="Delete"
    last_row=current_row
  end
  doc.to_html
end

def edit_card(html_doc, id)
  doc = Nokogiri::XML::Document.parse(html_doc)
  zindex = doc.at_css("input[name='index']")
  zindex['value']=id
  cards =DB[:cards]
  card = cards.first(:id=>id)
  simplified = doc.at_css("input[name='simplified']")
  simplified['value']=card[:simplified]
  traditional = doc.at_css("input[name='traditional']")
  traditional['value']=card[:traditional]
  pinyin = doc.at_css("input[name='pinyin']")
  pinyin['value']=card[:pinyin]
  english = doc.at_css("input[name='english']")
  english['value']=card[:english]
  doc.to_html
end

def update_card(params)
  cards=DB[:cards].where(:id=>params[:index])
  cards.update(:traditional=>params['traditional'],
               :simplified=>params['simplified'],
               :pinyin=>params['pinyin'],
               :english=>params['english'])
end

def delete_confirm(html_doc, id)
  doc = Nokogiri::XML::Document.parse(html_doc)
  card=DB[:cards].first(:id=>id)
  simplified=doc.at_css("span#simplified")
  simplified.content=card[:simplified]
  traditional=doc.at_css("span#traditional")
  traditional.content=card[:traditional]
  pinyin=doc.at_css("span#pinyin")
  pinyin.content=card[:pinyin]
  english=doc.at_css("span#english")
  english.content=card[:english]
  delete_link = doc.at_css("a#delete_url")
  delete_link['href']="/fc/delete/#{card[:id]}"
  doc.to_html
end

def delete_card(id)
  cards=DB[:cards].filter(:id=>id).delete
end

def inject_cedict_into_addcard (doc, character)
  @doc = Nokogiri::XML::Document.parse(doc)
  @cd_entry = search_simplified(character)
  @simplified_input = @doc.at_css 'div#add_to_deck input[name="simplified"]'
  @simplified_input['value']=@cd_entry[:simplified]
  @traditional_input = @doc.at_css 'div#add_to_deck input[name="traditional"]'
  @traditional_input['value']=@cd_entry[:traditional]
  @pinyin_input=@doc.at_css 'div#add_to_deck input[name="pinyin"]' 
  @pinyin_input['value']=@cd_entry[:pinyin]
  @english_input=@doc.at_css 'div#add_to_deck input[name="english"]'
  @english_input['value']=@cd_entry[:english] 
  @doc.to_html
end
