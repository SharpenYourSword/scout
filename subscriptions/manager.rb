require 'httparty'
require 'subscriptions/helpers'

module Subscriptions

  class Manager

    def self.search(subscription, options = {})
      poll subscription, :search, options
    end
    
    def self.initialize!(subscription)

      # allow overrides by individual adapters
      if subscription.adapter.respond_to?(:initialize!)
        subscription.adapter.initialize! subscription
      
      else
        # default strategy:
        # 1) does the initial poll
        # 2) stores every item ID as seen 

        # make initialization idempotent, remove any existing seen items first
        subscription.seen_ids.delete_all
        subscription.seen_items.delete_all

        Subscriptions::Manager.poll(subscription, :initialize).each do |item|
          # don't check if the seen ID already exists, for 
          # anticipated performance reasons (yes, premature optimization)
          mark_as_seen! subscription, item
        end
      end
      
      subscription.initialized = true
      subscription.last_checked_at = Time.now
      subscription.save!
    end
    
    def self.check!(subscription)
      
      # allow overrides by individual adapters
      if subscription.adapter.respond_to?(:check!)
        subscription.adapter.check! subscription

      else
        # default strategy:
        # 1) does a poll
        # 2) stores any items as yet unseen by this subscription in seen_ids
        # 3) stores any items as yet unseen by this subscription in the delivery queue
        if results = Subscriptions::Manager.poll(subscription, :check)
          results.each do |item|

            unless SeenId.where(:subscription_id => subscription.id, :item_id => item.id).first
              unless item.id
                Email.report Report.warning("Check", "[#{subscription.subscription_type}][#{subscription.keyword}] item with an empty ID")
                next
              end

              mark_as_seen! subscription, item
              schedule_delivery! subscription, item
            end
          end
        end
      end
      
      subscription.last_checked_at = Time.now
      subscription.save!
    end
    
    def self.schedule_delivery!(subscription, item)
      puts "[#{subscription.user.email}][#{subscription.subscription_type}][#{subscription.keyword}](#{item.id}) Scheduling delivery"
      
      Delivery.create!(
        :user_id => subscription.user.id,
        :user_email => subscription.user.email,
        
        :subscription_id => subscription.id,
        :subscription_type => subscription.subscription_type,
        :subscription_keyword => subscription.keyword,

        :keyword_id => subscription.keyword_id,
        
        :item_id => item.id,
        :item_date => item.date,
        :item_data => item.data,
        :item_search_url => item.search_url,
        :item_url => item.url
      )
    end

    def self.mark_as_seen!(subscription, item)
      SeenId.create! :subscription_id => subscription.id, :item_id => item.id
      SeenItem.create!(
        :subscription_id => subscription.id,
        :subscription_type => subscription.subscription_type,
        :subscription_keyword => subscription.keyword,

        :keyword_id => subscription.keyword_id,

        :item_id => item.id,
        :item_data => item.data,
        :item_date => item.date,
        :item_search_url => item.search_url,
        :item_url => item.url
      )
    end
    
    # function is one of [:search, :initialize, :check]
    def self.poll(subscription, function = :search, options = {})
      adapter = subscription.adapter
      url = adapter.url_for subscription, function, options
      
      puts "\n[#{subscription.subscription_type}][#{function}][#{subscription.keyword}][#{subscription.id}] #{url}\n\n" if config[:debug][:output_urls]
      
      begin
        response = HTTParty.get url
      rescue Timeout::Error, Errno::ETIMEDOUT => ex
        Email.report Report.warning("Poll", "[#{subscription.subscription_type}][#{function}][#{subscription.keyword}] poll timeout, returned an empty list")
        return [] # should be return nil, when we refactor this to properly accomodate failures in initialization, checking, and searching
      end
      
      results = adapter.items_for response, function, options
      
      if results
        results.map do |result| 
          # insert a reference to the subscription that generated result
          result.subscription = subscription

          # insert a reference to the URL this result was found in
          result.search_url = url
          result
        end
      else
        nil
      end
    end

    # given a type of adapter, and an item ID, fetch the item and return a Result item
    def self.find(adapter_type, item_id)
      adapter = Subscription.adapter_for adapter_type
      url = adapter.find_url item_id
      
      puts "\n[#{adapter}][find][#{item_id}] #{url}\n\n" if config[:debug][:output_urls]
      
      begin
        response = HTTParty.get url
      rescue Timeout::Error, Errno::ETIMEDOUT => ex
        Email.report Report.warning("Find", "[#{adapter_type}][find][#{item_id}] find timeout, returned nil")
        return nil
      end
      
      adapter.item_for response
    end
    
  end
  
  
  # utility class returned by adapters, then used to render displays and create various items in the database
  class Result
    
    # done so that when a template is rendered with this item as the context, 
    # it has all the subscription display helpers available to it
    include Subscriptions::Helpers
    include GeneralHelpers
    
    attr_accessor :id, :date, :data, :subscription, :search_url, :url
    
    def initialize(options)
      self.id = options[:id]
      self.date = options[:date]
      self.data = options[:data]

      # used when returning lists of results (set by manager)
      self.search_url = options[:search_url]
      self.subscription = options[:subscription]

      # used as a reference to find the exact item if needed (set by specific adapter)
      self.url = options[:url]
    end
    
  end
  
end