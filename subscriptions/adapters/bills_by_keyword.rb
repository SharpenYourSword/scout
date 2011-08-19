module Subscriptions  
  module Adapters

    class BillsByKeyword
      
      MAX_ITEMS = 20
      
      def self.url_for(subscription)
        # requires a query string
        return nil unless subscription.data['keyword'].present?
        
        api_key = config[:subscriptions][:sunlight_api_key]
        query = URI.escape subscription.data['keyword']
        sections = %w{ bill.bill_id bill.short_title bill.official_title bill.introduced_at bill.last_action_at }
        
        url = "http://api.realtimecongress.org/api/v1/search/bill_versions.json?apikey=#{api_key}"
        url << "&per_page=#{MAX_ITEMS}"
        url << "&query=#{query}"
        url << "&order=bill.last_action_at"
        url << "&sections=#{sections.join ','}"
        url << "&highlight=true"
      end
      
      # takes parsed response and returns an array where each item is 
      # a hash containing the id, title, and post date of each item found
      def self.items_for(response)
        items = []
        response['bill_versions'].each do |bv|
          items << item_for(bv)
        end
        items
      end
      
      
      # internal
      
      # returns a hash containing the id, title, and post date of the item
      def self.item_for(bill_version)
        
        title = bill_version["bill.short_title"].present? ? bill_version["bill.short_title"] : bill_version["bill.official_title"]
        
        Subscriptions::Item.new(
          :id => bill_version["bill.bill_id"],
          :title => title,
          :order_date => bill_version["bill.last_action_at"],
          :data => bill_version
        )
          
      end
    end
  
  end
end