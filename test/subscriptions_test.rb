require './test/test_helper'

class SubscriptionsTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include TestHelper::Methods


  # subscribing to new things -
  # identical parameters to search, it should be easy to get a one to one mapping
  # between the two, and to lookup whether a search has already been subscribed to
  def test_subscribe_to_searches_by_plain_keyword
    user = new_user!
    query = "environment"
    query2 = "copyright"
    
    assert_equal 0, user.subscriptions.count
    assert_equal 0, user.interests.count

    post "/subscriptions", {:subscription_type => "federal_bills", :query => query}, login(user)
    assert_response 200

    assert_equal 1, user.subscriptions.count
    assert_equal 1, user.interests.count

    assert_equal query, user.interests.first.in
    assert_equal query, user.subscriptions.first.interest_in
    assert_equal "federal_bills", user.subscriptions.first.subscription_type

    post "/subscriptions", {:subscription_type => "state_bills", :query => query}, login(user)
    assert_response 200

    assert_equal 2, user.subscriptions.count
    assert_equal 1, user.interests.count

    post "/subscriptions", {:subscription_type => "state_bills", :query => query2}, login(user)
    assert_response 200

    assert_equal 3, user.subscriptions.count
    assert_equal 2, user.interests.count

    # posting the same subscription should return 200, but be idempotent - nothing changed
    post "/subscriptions", {:subscription_type => "state_bills", :query => query2}, login(user)
    assert_response 200

    assert_equal 3, user.subscriptions.count
    assert_equal 2, user.interests.count

    # but if we include filter data, it's different!
    post "/subscriptions", {:subscription_type => "state_bills", :query => query2, :state_bills => {:state => "DE"}}, login(user)
    assert_response 200

    assert_equal 4, user.subscriptions.count
    assert_equal 2, user.interests.count

    # but, that data is also taken into account when finding duplicates
    post "/subscriptions", {:subscription_type => "state_bills", :query => query2, :state_bills => {:state => "DE"}}, login(user)
    assert_response 200

    assert_equal 4, user.subscriptions.count
    assert_equal 2, user.interests.count
  end

  def test_unsubscribe_from_individual_searches
    user = new_user!
    query1 = "environment"
    query2 = "guns"
    i1 = user.interests.create! :in => query1, :interest_type => "search"
    i2 = user.interests.create! :in => query2, :interest_type => "search"
    s1 = user.subscriptions.create! :interest => i1, :subscription_type => "state_bills", :interest_in => query1, :data => {"query" => query1}
    s2 = user.subscriptions.create! :interest => i1, :subscription_type => "federal_bills", :interest_in => query1, :data => {"query" => query1}
    s3 = user.subscriptions.create! :interest => i2, :subscription_type => "state_bills", :interest_in => query2, :data => {"query" => query2, 'state' => "CA"}

    delete "/subscriptions", {:subscription_type => s1.subscription_type, :query => s1.interest_in}, login(user)
    assert_response 200

    assert_not_nil Interest.find(i1.id)
    assert_nil Subscription.find(s1.id)
    assert_not_nil Subscription.find(s2.id)

    delete "/subscriptions", {:subscription_type => s2.subscription_type, :query => s2.interest_in}, login(user)
    assert_response 200

    assert_nil Interest.find(i1.id)    
    assert_nil Subscription.find(s2.id)

    delete "/subscriptions", {:subscription_type => s3.subscription_type, :query => s3.interest_in, s3.subscription_type => {'state' => 'DE'}}, login(user)
    assert_response 404

    assert_not_nil Interest.find(i2.id)
    assert_not_nil Subscription.find(s3.id)

    delete "/subscriptions", {:subscription_type => s3.subscription_type, :query => s3.interest_in, s3.subscription_type => {'state' => 'CA'}}, login(user)
    assert_response 200

    assert_nil Interest.find(i2.id)
    assert_nil Subscription.find(s3.id)
  end


  # Eventually: tests on subscriptions with no keyword at all


  def test_follow_item_and_then_unfollow
    item_id = "hr4192-112"
    interest_type = "bill"

    user = new_user!

    assert_equal 0, user.interests.count
    assert_equal 0, user.subscriptions.count

    item = SeenItem.new(:item_id => item_id, :date => Time.now, :data => {
      :bill_id => item_id,
      :enacted => true
    })
    Subscriptions::Manager.stub(:find).and_return(item)

    post "/item/#{interest_type}/#{item_id}/follow", {}, login(user)
    assert_response 200

    user.reload
    assert_equal 1, user.interests.count
    interest = user.interests.first
    assert_equal interest_data[interest_type][:subscriptions].keys.size, interest.subscriptions.count
    assert_equal item_id, interest.in
    assert_equal interest_data[interest_type][:subscriptions].keys.sort, interest.subscriptions.map(&:subscription_type).sort
  
    delete "/item/#{interest_type}/#{item_id}/unfollow", {}, login(user)
    assert_response 200

    user.reload
    assert_equal 0, user.interests.count
    assert_equal 0, user.subscriptions.count
  end

  # tragic
  def test_destroy_search_interest
    user = new_user!
    query = "environment"
    interest = user.interests.create! :in => query, :interest_type => "search"
    s1 = interest.subscriptions.create! :subscription_type => "federal_bills", :user_id => user.id, :interest_in => query
    s2 = interest.subscriptions.create! :subscription_type => "state_bills", :user_id => user.id, :interest_in => query

    delete "/interest/#{interest.id}", {}, login(user)
    assert_equal 200, last_response.status

    assert_nil Interest.find(interest.id)
    assert_nil Subscription.find(s1.id)
    assert_nil Subscription.find(s2.id)
  end

  def test_destroy_search_interest_not_users_own
    user = new_user!
    query = "environment"
    interest = user.interests.create! :in => query, :interest_type => "search"
    s1 = interest.subscriptions.create! :subscription_type => "federal_bills", :user_id => user.id, :interest_in => query
    s2 = interest.subscriptions.create! :subscription_type => "state_bills", :user_id => user.id, :interest_in => query

    user2 = new_user! :email => user.email.succ

    delete "/interest/#{interest.id}", {}, login(user2)
    assert_equal 404, last_response.status

    assert_not_nil Interest.find(interest.id)
    assert_not_nil Subscription.find(s1.id)
    assert_not_nil Subscription.find(s2.id)
  end

  def test_destroy_search_interest_not_logged_in
    user = new_user!
    query = "environment"
    interest = user.interests.create! :in => query, :interest_type => "search"
    s1 = interest.subscriptions.create! :subscription_type => "federal_bills", :user_id => user.id, :interest_in => query
    s2 = interest.subscriptions.create! :subscription_type => "state_bills", :user_id => user.id, :interest_in => query

    user2 = new_user! :email => user.email.succ

    delete "/interest/#{interest.id}"
    assert_equal 302, last_response.status

    assert_not_nil Interest.find(interest.id)
    assert_not_nil Subscription.find(s1.id)
    assert_not_nil Subscription.find(s2.id)
  end

  def test_update_interest_delivery_type

  end

  def test_update_interest_not_users_own
  end

  def test_update_interest_not_logged_in
  end

end