ENV['RACK_ENV'] = 'test'

require 'rubygems'
require 'test/unit'

require 'bundler/setup'
require 'rack/test'

require './scout'
require './test/factories'

require 'rspec/mocks'

set :environment, :test

module TestHelper

  module Methods

    # Test::Unit hooks

    def setup
      RSpec::Mocks.setup(self)

      Subscriptions::Manager.stub(:download).and_return("{}")
      Feedbag.stub(:find).and_return([])

      services = YAML.load_file File.join(File.dirname(__FILE__), "fixtures/services.yml")
      Environment.stub(:services).and_return(services)
    end

    def verify
      RSpec::Mocks.space.verify_all
    end

    # clearly should be replaced with something automatic
    def teardown
      User.delete_all
      Interest.delete_all
      Subscription.delete_all
      SeenItem.delete_all
      Tag.delete_all

      Delivery.delete_all
      Receipt.delete_all
      Report.delete_all

      ApiKey.delete_all
      Event.delete_all

      Cache.delete_all

      # remove rspec mocks
      RSpec::Mocks.space.reset_all
    end


    # factory for interests

    def search_interest!(user, search_type = "all", interest_in = "foia", query_type = "simple", filters = {}, attributes = {})
      interest = Interest.for_search user, search_type, interest_in, query_type, filters
      interest.attributes = attributes
      
      # will be harmless if fixture doesn't exist
      interest.ensure_subscriptions
      interest.subscriptions.each do |subscription|
        [:initialize, :check, :search].each do |function|
          path = fixture_path subscription, function
          if File.exists?("test/fixtures/#{path}.json")
            mock_search subscription, function
          end
        end
      end

      interest.save!
      interest
    end


    # mock helpers for faking remote content

    def mock_response(url, fixture)
      file = "test/fixtures/#{fixture}.json"
      if File.exists?(file)
        Subscriptions::Manager.should_receive(:download).with(url).and_return File.read(file)
      else
        Subscriptions::Manager.should_receive(:download).with(url).and_raise Errno::ECONNREFUSED.new
      end
    end

    def fixture_path(subscription, function = :search)
      "#{subscription.subscription_type}/#{subscription.interest_in}/#{function}"
    end

    def mock_search(subscription, function = :search)
      fixture = fixture_path subscription, function
      url = subscription.adapter.url_for subscription, function, {}
      mock_response url, fixture
    end

    def mock_item(item_id, item_type)
      subscription_type = item_types[item_type]['adapter']
      fixture = "#{subscription_type}/item/#{item_id}"
      url = Subscription.adapter_for(subscription_type).url_for_detail item_id
      mock_response url, fixture
    end

    # helper helpers
    class Anonymous; extend Helpers::Routing; end
    def routing; Anonymous; end


    # Sinatra helpers

    def app
      Sinatra::Application
    end

    def login(user)
      {"rack.session" => {'user_id' => user.id.to_s}}
    end

    def session(hash = {})
      {"rack.session" => hash}
    end

    # custom helpers

    def redirect_path
      if last_response.headers['Location']
        last_response.headers['Location'].sub(/http:\/\/example.org/, '')
      else
        nil
      end
    end

    def assert_response(status, message = nil)
      assert_equal status, last_response.status, (message || last_response.body)
    end

    def assert_redirect(path)
      assert_response 302
      assert_equal path, redirect_path
    end

    def json_response
      JSON.parse last_response.body
    end

  end
end