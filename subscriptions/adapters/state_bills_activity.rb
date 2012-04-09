module Subscriptions  
  module Adapters

    class StateBillsActivity
      
      def self.url_for(subscription, function, options = {})
        endpoint = "http://openstates.org/api/v1"
        api_key = config[:subscriptions][:sunlight_api_key]
        
        fields = %w{ bill_id state chamber session actions }
        
        item_id = subscription.interest_in

        # item_id is of the form ":state/:session/:chamber/:bill_id" (URI encoded already)
        url = "#{endpoint}/bills/#{URI.encode item_id.gsub('__', '/').gsub('_', ' ')}/?apikey=#{api_key}"
        url << "&fields=#{fields.join ','}"

        url
      end

      def self.short_name(number, subscription, interest)
        "#{number > 1 ? "actions" : "action"}"
      end
      
      def self.items_for(response, function, options = {})
        return nil unless response['actions']
        
        item_id = StateBills.id_for response.to_hash

        actions = []
        response['actions'].each do |action|
          actions << item_for(item_id, action)
        end
        actions
      end
      

      # private
      
      def self.item_for(item_id, action)
        return nil unless action

        action['date'] = action['date'].to_time

        SeenItem.new(
          :item_id => "#{item_id}-action-#{action['date'].to_i}",
          :date => action['date'],
          :data => action
        )
      end
      
    end
  
  end
end