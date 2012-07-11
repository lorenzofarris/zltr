#!/usr/bin/ruby

require 'sequel'
require 'Nokogiri'

DB=Sequel.sqlite('resources/zltdb')
Sequel.datetime_class = DateTime

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
               :chinese_ef=> 2.5 )              
end

def list_all_cards(html_doc)
  doc = Nokogiri::HTML::DocumentFragment.parse(html_doc)
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
  doc = Nokogiri::HTML::DocumentFragment.parse(html_doc)
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
  doc = Nokogiri::HTML::DocumentFragment.parse(html_doc)
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
  @doc = Nokogiri::HTML::DocumentFragment.parse(doc)
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
