require '../cards'

describe CardDB do
  before :all do
    @carddb = CardDB.new('sqlite:/')
    @carddb.new_db('../resources/cedict_1_0_ts_utf-8_mdbg.txt')
  end
  before :each do
    
  end
  describe '#search_simplified' do
    it "finds chinese to english dictionary entries" do
      @carddb.search_simplified('一')[:pinyin].should =='yi1' 
    end
  end
  
  describe '#import_deck' do
    it "loads new cards from a cedict style file" do
      
    end
  end
  
  describe '#export_deck' do
    it "exports flash cards as cedict style format" do
      
    end
  end
  describe '#list_all_cards' do
    
  end
  describe '#add_flashcard' do
    
  end
  describe '#edit_card' do
    
  end
  describe '#delete_card' do
    
  end
end

describe Deck do

end