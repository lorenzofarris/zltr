#!/usr/bin/ruby

require 'sequel'
require 'nokogiri'
require 'json'
require 'date'
require 'stringio'
require 'sinatra/base'

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

class DictionaryEntry < Sequel::Model(:cedict)
end


class CardDB

#  def initialize(resource_string='sqlite://resources/zltdb')
#    Sequel.datetime_class = DateTime
#    $stderr.puts "resource string is #{resource_string}"
#    @db = Sequel.connect(resource_string)
#    #check if the DB is already set up
#    unless @db.table_exists?(:cards)
#      new_db
#    end
#  end 
  
  def self.new_db(cedict_path="resources/cedict_1_0_ts_utf-8_mdbg.txt")
    create_cedict_table
    create_flashcards_table
    create_card_tries_table
    create_flashcard_memo_table
    load_cedict(cedict_path)
  end
  
  def create_cedict_table
    DB.create_table :cedict do
      primary_key :id
      String :traditional
      String :simplified
      String :pinyin
      String :english, :size=>1024
      String :line, :size=>2048
    end
  end

  def self.create_flashcards_table
    DB.create_table :cards do
      primary_key :id
      String :traditional
      String :simplified
      String :pinyin, :size=>1024
      String :english, :size=>2048
    end
  end
  
  def self.create_flashcard_memo_table
    DB.create_table :card_memo do
      primary_key :id
      foreign_key :card_id, :cards
      String :side # 'english' or 'chinese'
      DateTime :due
      Float :ef
      Integer :interval
    end
  end
    
  def self.create_card_tries_table
    DB.create_table :card_tries do
      primary_key :id
      DateTime :date
      foreign_key :card_memo_id, :card_memo
      Integer :q #supermemo quality factor
    end
  end 
  
  def self.create_review_cards_table
    DB.create_table :review_cards do
      primary_key :id
      foreign_key :card_memo_id, :card_memo
    end
  end
  
  def self.load_cedict(cedict_path, lines=0)
    cedict=DB[:cedict]
    counter=0             
    File.open(cedict_path,'r') do |f|
      f.readlines.each do |line|
        unless line=~/^#/
          # match everything up to the first open bracket, 
          # then match everything between the brackets
          # then match everything after the first closing bracket
          /^([^\[]+)\s*\[\s*([^\]]+)\s*\]\s*(\/.*\/)/ =~ line
          cc = $1
          py = $2
          eng = $3
          (t1, s1) = cc.split(/\s/);
          trad = t1.strip
          simp = s1.strip
          pinyin = py.strip
          # $puts "#{t1}@@#{s1}@@#{pinyin}@@#{eng}"
          cedict.insert(:traditional=>trad,
                        :simplified=>simp,
                        :pinyin=>pinyin,
                        :english=>eng,
                        :line=>line)
          counter += 1
          break if lines > 0 && counter > lines
        end
      end
    end
  end
  
  def self.search_simplified(simplified_character)
    #"your character is #{simplified_character}"
    entries=DB[:cedict].where(:simplified=>simplified_character).all
  end
  
  def self.import_cards(file)
    File.open(file,'r') do |f|
      f.readlines.each do |l|
        unless l=~/^#/
          /^([^\[]+)\s*\[\s*([^\]]+)\s*\]\s*(\/.*\/)/ =~ l
          cc = $1
          py = $2
          if py.nil? || py == "" 
            py=" "
          end
          eng = $3
          (t1, s1) = cc.split(/\s/);
          trad = t1.strip
          simp = s1.strip
          pinyin = py.strip
          add_flashcard({'traditional'=>trad,
                         'simplified'=>simp,
                         'pinyin'=>pinyin,
                         'english'=>eng})
        end
      end
    end
  end
  
  def self.export_cards(file="")
    buffer=""
    output=StringIO.open(buffer,"w")
    DB[:cards].each do |card|
      if /^\/.*\/$/ =~  card[:english]
        english = "#{card[:english]}"
      else
        english = "/#{card[:english]}/"
      end 
      output.puts "#{card[:traditional]} #{card[:simplified]} [#{card[:pinyin]}] #{english}\n"
      #output.puts "#{card[:english]}\n" if /^\/.*\/$/=~card[:english]
      #output.puts "#{english}\n"
    end
    unless file==""
      output=File.open(file,"w")
      output.puts(buffer)
    end
    buffer
  end
  
  def self.repeat_card
    rcard=ReviewCard.first
    ncard = ReviewCard.new(:card_memo=>rcard.card_memo)
    rcard.delete
    ncard.save
  end
  
  def self.score_card(score)
    if score < 4
      repeat_card 
    else
      record_score(score)
    end
  end
        
  def self.record_score(score)
    rcard=ReviewCard.first
    card_memo=rcard.card_memo
    card=card_memo.card
    # calculate ease-factor
    new_ef(score, card_memo)
    # calculate next interval
    new_interval()
    t = CardTry.new(:card_memo=>card_memo)
    t.date=DateTime.now
    t.q=score
    t.save
    # drop the card off the review stack
    rcard.delete
    ReviewCard.all.length
  end
  
  def self.new_interval
    # assume ease factor has already been updated
    # update the repetition interval in days for the card
    # which is needed for calculations, and
    # the next due date for review of the card
    rcard=ReviewCard.first
    card_memo=rcard.card_memo
    new_interval = (card_memo.interval * card_memo.ef).round
    card_memo.interval = new_interval
    card_memo.due = DateTime.now + new_interval
    card_memo.save
  end   
  
  def self.new_ef(score, card_memo)
    # calculated values from supermemo2 algorithm
    # score should be from 1 to 5
    return nil unless (1 <= score) && (score <= 5)
    ef_adder = [-1, -0.54, -0.32, -0.14, 0, 0.1]
    new_ef=card_memo.ef + ef_adder[score]
    card_memo.ef = new_ef < 1.3 ? 1.3 : new_ef
    card_memo.save
  end
  
  def self.get_cards_due(number=20)
      cards=CardMemo.order(:due).limit(number).all
      cards.shuffle!
      cards.each do |c|
        ReviewCard.new(:card_memo=>c).save
      end
  end

  def self.add_flashcard(mapp)
    # updated, using Sequel ORM
    c = Card.new
    c.traditional = mapp['traditional']
    c.simplified = mapp['simplified']
    c.pinyin = mapp['pinyin']
    c.english = mapp['english']
    c.save
    cz=add_memo('chinese')
    c.add_card_memo(cz)
    cz=add_memo('english')
    c.add_card_memo(cz)
  end
 
  def self.add_memo(type)
    #updated, using Sequel ORM
    cz = CardMemo.new
    cz.side = type
    cz.due = DateTime.now
    cz.ef = 2.5
    cz.interval = 1
    cz.save    
  end
    
  def self.render_card_review(html)
    # will return a Nokogiri doc
    # get a review deck, if I haven't got one
    rcards=ReviewCard.all
    if rcards.length==0
      get_cards_due(20)
    end
    rcard=ReviewCard.first
    card_memo=rcard.card_memo
    card=card_memo.card
    type=card_memo.side
    doc = Nokogiri::HTML::Document.parse(html)    
    front=doc.at_css("#front")
    back=doc.at_css("#back")
    if type=="chinese"
      front_visible=front.at_css(".character")
      front_visible.delete('hidden') if front_visible.key?('hidden')
      front_visible.content=card[:simplified]
      back_pinyin=back.at_css(".pinyin")
      back_pinyin.content=card[:pinyin]
      back_english=back.at_css(".english")
      back_english.content=card[:english]
    else
      front_visible=front.at_css(".english")
      front_visible.delete('hidden') if front_visible.key?('hidden')
      front_visible.content=card[:english]
      back_pinyin=back.at_css(".pinyin")
      back_pinyin.content=card[:pinyin]
      back_character=back.at_css(".character")
      back_character.content=card[:simplified]
    end
    doc
  end
  
  def self.render_card_review_front(html)
    #$stderr.puts "in render_card_review_front"
    doc=render_card_review(html)
    check_form=doc.at_css("#check")
    check_form.delete('hidden') if check_form.key?('hidden')
    doc.to_html
  end
  
  def self.render_card_review_full(html)
    rcards=ReviewCard.all
    if rcards.length==0
      get_cards_due(20)
    end
    rcard=ReviewCard.first
    card_memo=rcard.card_memo
    card=card_memo.card
    type=card_memo.side
    doc=render_card_review(html)
    back=doc.at_css("#back")
    if type=="chinese"
      back_pinyin=back.at_css(".pinyin")
      back_pinyin.delete('hidden') if back_pinyin.key?('hidden')
      back_english=back.at_css(".english")
      back_english.delete('hidden') if back_english.key?('hidden')
    else
      back_pinyin=back.at_css(".pinyin")
      back_pinyin.delete('hidden') if back_pinyin.key?('hidden')
      back_character=back.at_css(".character")
      back_character.delete('hidden') if back_character.key?('hidden')
    end
    check_form=doc.at_css("#score")
    check_form.delete('hidden') if check_form.key?('hidden')
    doc.to_html
  end
  
  def self.list_all_cards(html_doc, root_url)
    # $stderr.puts(html_doc)
    $stderr.puts("root_url=#{root_url}")
    doc = Nokogiri::HTML::Document.parse(html_doc)
    $stderr.puts("parsed and re-rendered: #{doc.to_html}")
    current_row = doc.at_css("tr.card_row")
    last_row=current_row
    first_row_flag=true
    Card.all.each  do |card|
      # already have first row in the template for layout purposes
      unless first_row_flag
        current_row=last_row.dup
        last_row.add_previous_sibling(current_row)
      else
        first_row_flag=false
      end
      current_row.at_css("td.traditional").content=card[:traditional]
      current_row.at_css("td.simplified").content=card[:simplified]
      current_row.at_css("td.pinyin").content=card[:pinyin]
      current_row.at_css("td.english").content=card[:english]
      a1 = current_row.at_css("td.index a")
      a1['href']= root_url + "/edit/#{card[:id]}"
      a1.content="Edit"
      a2 = current_row.at_css("td.delete a")
      a2['href']= root_url + "/delete-confirm/#{card[:id]}"
      a2.content="Delete"
      last_row=current_row
    end
    $stderr.puts doc.to_html
    doc.to_html
  end
  
  def self.edit_card(html_doc, id)
    doc = Nokogiri::HTML::Document.parse(html_doc)
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
   
  def self.update_card(params)
    card=Card[params[:index]]
    card.traditional=params['traditional']
    card.simplified=params['simplified']
    card.pinyin=params['pinyin']
    card.english=params['english']
    card.save
  end
 
  def self.delete_confirm(html_doc, id)
    doc = Nokogiri::HTML::Document.parse(html_doc)
    card=Card[id]
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
  
  def self.delete_card(id)
    card=Card[id]
    card.remove_all_card_memo
    card.delete
  end
  
  def self.render_cedict_choices(htmldoc, params)
    doc = Nokogiri::HTML::Document.parse(htmldoc)
    # if I've got only the simplified character parameter set,
    # I need to do a lookup, otherwise I've already got all
    # I need from the cedict database
    if params.key?('english')
      inject_cedict_into_addcard(doc, params)
    else
      entries = search_simplified(params[:simplified])
      if entries.nil? or entries.length==0 
        results=doc.at_css "div#results"
        results.content="Character #{params[:simplified]} not found."
      elsif entries.length==1
        $stderr.puts entries[0]
        inject_cedict_into_addcard(doc, entries[0])
      else
        choices = doc.at_css "div#choices"
        choices.delete("hidden") if choices.key?("hidden")
        row=choices.at_css "tr.data"
        # I really want a "do-while" here
        next_row=nil
        first_row=true
        entries.each do |entry|
          unless first_row
            next_row = row.dup()
            row.add_next_sibling next_row
            row = next_row
          else
            first_row=false
          end
          traditional=row.at_css "td.traditional"
          traditional.content = entry[:traditional]
          simplified=row.at_css "td.simplified"
          simplified.content = entry[:simplified]
          pinyin=row.at_css "td.pinyin"
          pinyin.content = entry[:pinyin]
          english=row.at_css "td.english"
          english.content = entry[:english]
          form_input = row.at_css "input.traditional"
          form_input['value']=entry[:traditional]
          form_input = row.at_css "input.simplified"
          form_input['value']=entry[:simplified]
          form_input = row.at_css "input.pinyin"
          form_input['value']=entry[:pinyin]
          form_input = row.at_css "input.english"
          form_input['value']=entry[:english]         
        end
      end
    end 
    doc.to_html    
  end  

  def self.inject_cedict_into_addcard (doc, params)
    #$stderr.puts "params is #{params}"
    #doc = Nokogiri::HTML::Document.parse(htmldoc)
    unless params.nil? || params.length < 1
      #$stderr.puts "building my form"
      simplified_input = doc.at_css 'div#add_to_deck input[name="simplified"]'
      #$stderr.puts "simplfied = #{params[:simplified]}"
      simplified_input['value']=params[:simplified]
      #$stderr.puts simplified_input.to_html
      traditional_input = doc.at_css 'div#add_to_deck input[name="traditional"]'
      traditional_input['value']=params[:traditional]
      pinyin_input=doc.at_css 'div#add_to_deck input[name="pinyin"]' 
      pinyin_input['value']=params[:pinyin]
      english_input=doc.at_css 'div#add_to_deck textarea[name="english"]'
      english_input.content=params[:english]
      snippet = doc.at_css 'div#add_to_deck'
      #$stderr.puts snippet.to_html
    else
      results=doc.at_css "div#results"
      results.content="Character #{params[:simplified]} not found."
    end 
    doc
  end
  
  def self.review_cards_left?
    rcards=ReviewCard.all
    return false if rcards.length==0
    return true if rcards.length>0
    false  
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
  unless @cd_entry.nil? || @cd_entry.length < 1
    @simplified_input = @doc.at_css 'div#add_to_deck input[name="simplified"]'
    @simplified_input['value']=@cd_entry[:simplified]
    @traditional_input = @doc.at_css 'div#add_to_deck input[name="traditional"]'
    @traditional_input['value']=@cd_entry[:traditional]
    @pinyin_input=@doc.at_css 'div#add_to_deck input[name="pinyin"]' 
    @pinyin_input['value']=@cd_entry[:pinyin]
    @english_input=@doc.at_css 'div#add_to_deck textarea[name="english"]'
    @english_input.content=@cd_entry[:english]
  else
    @results=@doc.at_css "div#results"
    @results.content="Character #{character} not found."
  end 
  @doc.to_html
end

class Card < Sequel::Model
  one_to_many :card_memo
end

class CardMemo < Sequel::Model(:card_memo)
  many_to_one :card
  one_to_many :review_cards
  one_to_many :card_tries
end

class CardTry <Sequel::Model
  many_to_one :card_memo
end

class ReviewCard < Sequel::Model
  many_to_one :card_memo
end
