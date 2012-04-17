module Subscriptions  
  module Adapters

    class StateBills
      
      def self.url_for(subscription, function, options = {})
        api_key = options[:api_key] || config[:subscriptions][:sunlight_api_key]

        endpoint = "http://openstates.org/api/v1"
        query = URI.escape subscription.interest_in
        
        fields = %w{ id bill_id subjects state chamber created_at updated_at title sources versions session %2Bshort_title }
        
        url = "#{endpoint}/bills/?apikey=#{api_key}"
        
        url << "&fields=#{fields.join ','}"
        url << "&q=#{query}"
        url << "&search_window=all"
        
        if subscription.data['state'].present?
          url << "&state=#{subscription.data['state']}"
        end

        if function == :search or function == :initialize
          url << "&sort=created_at"
        elsif function == :check
          updated_since = subscription.last_checked_at.strftime("%Y-%m-%dT%H:%M:%S")
          url << "&updated_since=#{updated_since}"
        end

        url
      end

      def self.search_name(subscription)
        if subscription.data['state']
          "#{ScoutUtils.state_map[subscription.data['state']]} Bills"
        else
          "State Bills"
        end
      end

      def self.short_name(number, subscription, interest)
        "#{subscription.data['state'] || "state"} #{number > 1 ? "bills" : "bill"}"
      end

      def self.interest_name(interest)
        "#{interest.data['bill_id']} (#{interest.data['state'].upcase})"
      end

      # item_id in this case is not actually the remote bill_id, since that's not specific enough
      def self.url_for_detail(item_id, options = {})
        api_key = options[:api_key] || config[:subscriptions][:sunlight_api_key]
        
        endpoint = "http://openstates.org/api/v1"
        
        fields = %w{ id bill_id state chamber created_at updated_at title sources actions votes session versions %2Bshort_title }
        
        # item_id is of the form ":state/:session/:chamber/:bill_id" (URI encoded already)
        url = "#{endpoint}/bills/#{URI.encode item_id.gsub('__', '/').gsub('_', ' ')}/?apikey=#{api_key}"
        url << "&fields=#{fields.join ','}"

        url
      end
      
      # takes parsed response and returns an array where each item is 
      # a hash containing the id, title, and post date of each item found
      def self.items_for(response, function, options = {})
        return if response.is_a?(String)
        
        # OpenStates API does not have server-side pagination - so we do it here
        per_page = options[:per_page] || 20
        page = options[:page] || 1
        beginning = per_page * (page - 1) # index of first item
        ending = (beginning + per_page) - 1  # index of last item

        # for searching, only return the first "page" of items, otherwise, handle any and all
        items = (function == :search) ? (response[beginning..ending] || []) : response

        items.map {|bill| item_for bill}
      end

      def self.item_detail_for(bill)
        item_for bill.to_hash
      end
      
      # internal
      
      def self.item_for(bill)
        # manually parse all of the dates - so lame, not sure why HTTParty is so bad at the format OpenStates uses

        # updated_at is UTC, take it directly as such
        bill['updated_at'] = bill['updated_at'] ? bill['updated_at'].to_time : nil

        if bill['actions']
          bill['actions'].each do |action|
            action['date'] = Time.parse(action['date']) if action['date']
          end
        end

        if bill['votes']
          bill['votes'].each do |vote|
            vote['date'] = Time.parse(vote['date']) if vote['date']
          end
        end

        # save the item ID as a piece of the URL we can plug back into the OS API later
        SeenItem.new(
          :item_id => bill['id'],
          :date => bill["created_at"],
          :data => bill
        )
      end

      # cast dates with an unknown time zone to noon UTC, to make sure at least the day is always correct
      def self.noon_utc_for(date)
        date.to_time.midnight + 12.hours
      end
      
    end
    
  end
end