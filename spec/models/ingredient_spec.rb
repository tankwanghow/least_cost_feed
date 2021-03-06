require 'spec_helper'

describe Ingredient do
  let(:i) { create :ingredient }
  let(:ic1) { create :ingredient_composition, ingredient_id: i.id }
  let(:ic2) { create :ingredient_composition, ingredient_id: i.id }
  let(:ic3) { create :ingredient_composition, ingredient_id: i.id }
  let(:user_1) { create :active_user }
  before(:each) { User.stub(:current).and_return user_1 }

  it { should have_db_column(:user_id).with_options(null: false) }
  it { should have_db_column(:name).with_options(null: false) }
  it { should have_db_column(:cost).with_options(null: false, default: 0.0, precision: 12, scale: 4) }
  it { should have_db_column(:lock_version).with_options(default: 0, null: false) }
  it { should have_db_column(:package_weight).with_options(default: 0.1) }
  it { should have_db_column(:note) }
  it { should have_db_column(:status).with_options(default: 'using', null: false) }
  it { should have_db_column(:category).with_options(default: 'private', null: false) }

  it { should validate_numericality_of(:cost).is_greater_than_or_equal_to(0.0) } 
it { should validate_numericality_of(:package_weight).is_greater_than_or_equal_to(0.0) } 

  it { should have_db_index([:user_id, :name]).unique(true) }
  it { should validate_presence_of :name }
  it { should validate_presence_of :cost }
  it { should validate_presence_of :status }
  it { should validate_presence_of :category }
  it { should have_many(:ingredient_compositions).dependent(:destroy) }

  it "should be timestamped" do
    should have_db_column :created_at
    should have_db_column :updated_at
  end

  it { i; should validate_uniqueness_of(:name).scoped_to(:user_id) }
  it { should belong_to :user }
  it { should accept_nested_attributes_for :ingredient_compositions }

  context "self.find_ingredients" do
    let(:user_2) { create :active_user }
    before(:each) do
      9.times { create :ingredient, user_id: user_1.id }
      7.times { create :ingredient, user_id: user_2.id }
    end
    it { expect(Ingredient.find_ingredients('sam', 1)).to eq user_1.ingredients.where("name || status || category ilike '%sam%'").page(1).per(25).order(:name) }
    it { expect(Ingredient.find_ingredients).to eq user_1.ingredients.page(1).per(25).order(:name) }
  end

  it 'self.create_like' do
    i.ingredient_compositions << ic1
    i.ingredient_compositions << ic2
    i.ingredient_compositions << ic3
    i.save
    a = Ingredient.create_like i.id
    expect(a.name).to           include i.name
    expect(a.user_id).to        eq i.user_id
    expect(a.cost).to           eq i.cost
    expect(a.package_weight).to eq i.package_weight
    expect(a.note).to           eq i.note
    expect(a.category).to       eq i.category
    i.ingredient_compositions.each do |t|
      expect(a.ingredient_compositions.find { |k| k.nutrient == t.nutrient }.value).to eq t.value
    end
    Ingredient.count.should == 2
  end
end
