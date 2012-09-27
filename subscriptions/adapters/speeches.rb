module Subscriptions
  module Adapters

    class Speeches

      def self.filters
        {
          "state" => {
            name: -> code {StateBills.state_map[code]}
          },
          "party" => {
            name: -> party {party_map[party]}
          },
          "chamber" => {
            name: -> chamber {chamber.capitalize}
          }
        }
      end
      
      def self.url_for(subscription, function, options = {})
        api_key = options[:api_key] || config[:subscriptions][:sunlight_api_key]
        
        endpoint = "http://capitolwords.org/api"

        # speeches don't support citations
        query = subscription.query['query'] || subscription.query['original_query']
        return nil unless query.present?

        
        url = "#{endpoint}/text.json?apikey=#{api_key}"
        url << "&q=#{CGI.escape query}"

        # keep it only to fields with a speaker (bioguide_id)
        url << "&bioguide_id=[''%20TO%20*]"

        # filters

        ["state", "party"].each do |field|
          if subscription.data[field].present?
            url << "&#{field}=#{CGI.escape subscription.data[field]}"
          end
        end

        # pagination

        url << "&page=#{options[:page].to_i - 1}" if options[:page]
        url << "&per_page=#{options[:per_page]}" if options[:per_page]

        url << "&sort=date%20desc"
        
        url
      end

      def self.url_for_detail(item_id, options = {})
        api_key = options[:api_key] || config[:subscriptions][:sunlight_api_key]
        
        endpoint = "http://capitolwords.org/api"
        
        url = "#{endpoint}/text.json?apikey=#{api_key}"
        url << "&id=#{item_id}"
        
        url
      end

      def self.search_name(subscription)
        "Speeches in Congress"
      end
      
      def self.short_name(number, interest)
        "#{number > 1 ? "speeches" : "speech"}"
      end
      
      # takes parsed response and returns an array where each item is 
      # a hash containing the id, title, and post date of each item found
      def self.items_for(response, function, options = {})
        raise AdapterParseException.new("Response didn't include 'results' field: #{response.inspect}") unless response['results']
        
        #TODO: hopefully get the API changed to allow filtering on only spoken results
        response['results'].map do |result|
          item_for result
        end
      end
      
      def self.item_detail_for(response)
        item_for response['results'][0]
      end
      
      
      # internal
      
      def self.item_for(result)
        return nil unless result

        result['date'] = Subscriptions::Manager.noon_utc_for result['date']
        result['date_year'] = result['date'].year
        result['date_month']= result['date'].month
        result['date_day'] = result['date'].day
        
        matches = result['origin_url'].scan(/Pg([\w\d-]+)\.htm$/)
        if matches.any?
          result['page_slug'] = matches.first
        end
        
        SeenItem.new(
          :item_id => result['id'],
          :date => result['date'],
          :data => result
        )
          
      end
      
      def self.party_map
        @party_map ||= {
          "R" => "Republican",
          "D" => "Democrat",
          "I" => "Independent"
        }
      end
      
    end
  
  end
end