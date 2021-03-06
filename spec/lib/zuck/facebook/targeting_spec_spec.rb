require 'spec_helper'

describe Zuck::TargetingSpec do
  let(:ad_account) { "2ijdsfoij" }
  let(:graph) { mock('koala') }

  describe "validating interests" do

    let(:valid_interest_result) { [{"name" => "foo", "valid" => true}] }
    let(:invalid_interest_result) { [] }


    it "acknowledges valid interests" do
      graph.should_receive(:search).with('foo', type: :adinterest).and_return(valid_interest_result)
      #graph.should_not_receive(:search)
      fts = Zuck::TargetingSpec.new(graph, ad_account)

      fts.validate_interest('foo').should == true
    end

    it "refuses invalid interests" do
      graph.should_receive(:search).with('sdjf', type: :adinterest).and_return(invalid_interest_result)
      fts = Zuck::TargetingSpec.new(graph, ad_account)

      fts.validate_interest('sdjf').should == false
    end
  end

  describe "options given in spec" do
    it "accepts male as gender" do
      expect {
        Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['US']}, interests: [{id: '123', name: 'foo'}], gender: 'male')
      }.to_not raise_error
    end

    it "accepts male as gender for young people" do
      expect {
        Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['US']}, interests: [{id: '123', name: 'foo'}], gender: 'male', age_class: 'young')
      }.to_not raise_error
    end

    it "accepts male as gender for old people" do
      expect {
        Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['US']}, interests: [{id: '123', name: 'foo'}], gender: 'male', age_class: 'old')
      }.to_not raise_error
    end

    it "accepts without gender" do
      expect {
        Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['US']}, interests: [{id: '123', name: 'foo'}])
      }.to_not raise_error
    end

    it "accepts single keyword" do
      expect {
        Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['US']}, interest: 'foo')
      }.to_not raise_error
    end

    it "does not accept invalid genders" do
      expect {
        Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['US']}, interests: [{id: '123', name: 'foo'}], gender: 'gemale')
      }.to raise_error("Gender can only be male or female")
    end

    it "does not accept invalid countries" do
      expect {
        z = Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['XX']}, interests: [{id: '123', name: 'foo'}], gender: 'female')
        z.send(:validate_spec)
      }.to raise_error('Invalid countrie(s): ["XX"]')
    end


    it "does not accept targetings with neither :interests nor :connections" do
      expect {
        ts = Zuck::TargetingSpec.new(graph, ad_account, geo_locations: {countries: ['US']}, gender: 'female')
        ts.fetch_reach
      }.to raise_error("Need to set :interests or :connections")
    end
  end

  describe "fetching reach" do
    let(:graph) { Koala::Facebook::API.new(test_access_token) }
    let(:ad_account) { test_account_id }

    it "bugs out when trying to use an invalid interest" do
      VCR.use_cassette('reach_for_invalid_interest') do
        spec = {geo_locations: {countries: ['us']}, interests: ['Eminem', 'invalidsssssssssssssss']}
        ts = Zuck::TargetingSpec.new(graph, ad_account, spec)
        expect {
          ts.validate_interests
        }.to raise_error(Zuck::InvalidKeywordError, 'invalidsssssssssssssss')
      end
    end

    it "works without gender or age" do
      VCR.use_cassette('reach_for_valid_keywords') do
        spec = {geo_locations: {countries: ['us']}, interests: [{id: '6003135347608', name: 'Eminem'}, {id: '6003504886186', name: 'Sting (musician)'}]}
        ts = Zuck::TargetingSpec.new(graph, ad_account, spec)
        explain_error {
          reach = ts.fetch_reach
          reach[:users].should == 31_00_0000
        }
      end
    end

    it "works with gender and age" do
      VCR.use_cassette('reach_for_valid_keywords_male_young') do
        spec = {geo_locations: {countries: ['us']}, interests: [{id: '6003504886186', name: 'Sting (musician)'}], gender: :female, age_class: :young}
        ts = Zuck::TargetingSpec.new(graph, ad_account, spec)
        explain_error {
          reach = ts.fetch_reach
          reach[:users].should == 63_000
        }
      end
    end

    it "without instanciating manually" do
      x = stub()
      x.should_receive(:fetch_reach).and_return 9
      Zuck::TargetingSpec.should_receive(:new).with(:graph, :ad_account, :options).and_return x

      Zuck::TargetingSpec.fetch_reach(:graph, :ad_account, :options)
    end

  end

  describe "Batch processing" do
    let(:graph) { Koala::Facebook::API.new(test_access_token) }
    let(:ad_account) { test_account_id }
    let(:spec_mock) { mock(fetch_reach: {some: :data}) }

    it "fetches each reach" do
      requests = [{some: :thing}] * 51
      Zuck::TargetingSpec.should_receive(:new).exactly(51).and_return spec_mock
      Zuck::TargetingSpec.batch_reaches(graph, ad_account, requests)
    end
    it "doesn't split up small bunches" do
      requests = [{some: :thing}] * 50
      graph.should_receive(:batch).once.and_return([])
      Zuck::TargetingSpec.batch_reaches(graph, ad_account, requests)
    end

    it "splits up into 50 request bunches" do
      requests = [{some: :thing}] * 51
      graph.should_receive(:batch).twice.and_return([])
      Zuck::TargetingSpec.batch_reaches(graph, ad_account, requests)
    end

    it "reformats results including errors" do
      responses = [{facebook: :response}, Koala::KoalaError.new]
      requests = [{some: :thing}] * 51
      graph.should_receive(:batch).twice.and_return(responses)
      reaches = Zuck::TargetingSpec.batch_reaches(graph, ad_account, requests)

      reaches[0][:success].should == true
      reaches[1][:success].should == false
    end
  end
end
