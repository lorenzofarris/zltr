# db.rb
# Sets up the database for the app

require 'sequel'

DB=Sequel.sqlite('resources/zltdb')
Sequel.datetime_class = DateTime
  
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

def create_flashcards_table
  DB.create_table :cards do
    primary_key :id
    String :traditional
    String :simplified
    String :pinyin, :size=>1024
    String :english, :size=>2048
    DateTime :english_due
    Datetime :chinese_due
    Float :english_ef
    Float :chinese_ef
    Integer :english_interval
    Integer :chinese_interval
  end
end

def create_card_tries
  DB.create_table :card_tries do
    primary_key :id
    DateTime :date
    foreign_key :card, :cards
    Integer :side #chinese is front is 1, english is back is 2
    Integer :q #supermemo quality factor
  end
end

def load_cedict
  cedict=DB[:cedict]                         
  File.open("resources/cedict_1_0_ts_utf-8_mdbg.txt",'r') do |f|
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
        puts "#{t1}@@#{s1}@@#{pinyin}@@#{eng}"
        cedict.insert(:traditional=>trad,
                      :simplified=>simp,
                      :pinyin=>pinyin,
                      :english=>eng,
                      :line=>line)
      end
    end
  end
end

def build_new_db
  create_cedict_table
  create_flashcards_table
  create_card_tries
  load_cedict
end