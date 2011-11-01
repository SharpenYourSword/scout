require 'sinatra'
require 'mongoid'
require 'tzinfo'

def config
  @config ||= YAML.load_file File.join(File.dirname(__FILE__), "config.yml")
end

configure do
  config[:mongoid][:logger] = Logger.new config[:log_file] if config[:log_file]
  Mongoid.configure {|c| c.from_hash config[:mongoid]}
end

# app-wide models and helpers
Dir.glob('models/*.rb').each {|filename| load filename}
require 'helpers'

# email utilities
require 'config/email'

# subscription-specific adapters and management
Dir.glob('subscriptions/adapters/*.rb').each {|filename| load filename}
require 'subscriptions/manager'
require 'subscriptions/deliverance'

def subscription_data 
  {
    'federal_bills' => {
      :name => "Congress' Bills",
      :description => "bills in Congress",
      :group => "congress",
      :order => 1,
      :color => "#46517A"
    },
    'state_bills' => {
      :name => "State Bills",
      :description => "bills in the states",
      :group => "states",
      :order => 3,
      :color => "#467A62"
    },
    'congressional_record' => {
      :name => "Congress' Speeches",
      :description => "speeches",
      :group => "congress",
      :order => 2,
      :color => "#51467A"
    }
  }
end