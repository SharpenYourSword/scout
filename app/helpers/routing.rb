# router helpers, can also be mixed in elsewhere if need be

module Helpers
  module Routing

    # for item interests
    def interest_adapter(interest)
      Subscription.adapter_for(item_types[interest.item_type]['adapter'])
    end

    def interest_name(interest)
      if interest.item?
        interest_adapter(interest).interest_name interest
      elsif interest.feed?
        interest.data['title']
      elsif interest.search?
        interest.in
      elsif interest.tag?
        interest.tag.name
      end
    end

    def interest_description(interest)
      if interest.search?
        if interest.search_type == "all"
          interest.subscriptions.map(&:search_name).join(", ")
        elsif interest.subscriptions.first.filters.any?
          filters_short interest.subscriptions.first
        end
      elsif interest.item?
        if interest_adapter(interest).respond_to?(:interest_subtitle)
          truncate interest_adapter(interest).interest_subtitle(interest), 75
        end
      elsif interest.feed?
        truncate interest.data['description'], 75
      elsif interest.tag?
        truncate interest.tag.description, 75
      end
    end

    def interest_feed_path(interest)
      if interest.feed?
        interest.data['url']
      elsif interest.tag?
        tag_feed_path interest.tag_user, interest.tag, "rss"
      else
        "/interest/#{interest.id}.rss"
      end
    end

    def interest_json_path(interest)
      if interest.tag?
        tag_feed_path interest.tag_user, interest.tag, "json"
      else
        "/interest/#{interest.id}.json"
      end
    end

    def interest_path(interest)
      if interest.item?
        "/item/#{interest.item_type}/#{interest.in}"
      elsif interest.feed?
        interest.data['site_url'] || interest.data['url'] # URL
      elsif interest.search?
        search_interest_path interest
      elsif interest.tag?
        tag_path interest.tag_user, interest.tag
      end
    end

    def interest_url(interest)
      "http://#{config[:hostname]}#{interest_path interest}"
    end

    def search_interest_path(interest)
      if interest.search_type == "all"
        base = "/search/all"
        base << "/#{URI.encode interest.data['query']}" if interest.data['query']
        base
      else
        subscription_path interest.subscriptions.first
      end
    end

    # given a subscription, serialize it to a URL
    # assumes it is a search subscription
    def subscription_path(subscription)
      base = "/search/#{subscription.subscription_type}"
      
      base << "/#{URI.encode subscription.data['query']}"

      base << "/advanced" if subscription.data['query_type'] == 'advanced'
      
      query_string = subscription.filters.map do |key, value| 
        "#{subscription.subscription_type}[#{key}]=#{URI.encode value}"
      end.join("&")

      base << "?#{query_string}" if query_string.present?

      base
    end
    
    def item_path(item)
      if item.item?
        "/item/#{item.item_type}/#{item.interest_in}##{item.item_id}"
      elsif item.feed?
        item.data['url']
      elsif item.search?
        "/item/#{item.item_type}/#{item.item_id}"
      end
    end

    def item_url(item)
      if item.subscription_type == "feed"
        item.data['url']
      else
        "http://#{config[:hostname]}#{item_path item}"
      end
    end

    def user_id(user)
      user.username || user.id.to_s
    end

    def tag_path(user, tag)
      "/user/#{user_id user}/#{Tag.slugify tag.name}"
    end

    def tag_feed_path(user, tag, format)
      "#{tag_path user, tag}.#{format}"
    end

    # only needed in RSS feeds, and external feeds are the only time we override the guid
    def item_guid(item)
      if item.subscription_type == "feed"
        item.data['guid']
      else
        item_url item
      end
    end

    # URLs for the JSON feeds behid the searches, but with the user's API key
    def developer_search_url(subscription)
      subscription.search_url :api_key => api_key
    end

    def developer_find_url(item_type, item_id)
      adapter = Subscription.adapter_for item_types[item_type]['adapter']
      adapter.url_for_detail item_id, :api_key => api_key
    end

    # shrug
    def searching?
      request.path =~ /^\/search\//
    end

  end
end