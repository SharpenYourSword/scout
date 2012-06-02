require './test/test_helper'

class RemoteTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include TestHelper::Methods
  include FactoryGirl::Syntax::Methods

  def test_subscribe_by_sms
    phone = "+15555551212"
    item_id = "hr4192-112"
    item_type = "bill"

    mock_item item_id, item_type

    assert_nil User.where(:phone => phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    # verify SMS was sent to the user telling them to confirm
    SMS.should_receive(:deliver!).with("Remote Subscription", phone, anything)

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 200

    user = User.where(:phone => phone).first
    assert_not_nil user

    assert !user.confirmed?
    assert_equal "none", user.notifications

    assert_not_nil user.password_hash
    assert user.should_change_password
    assert_equal "testing", user.source

    assert_equal phone, user.phone
    assert !user.phone_confirmed?

    assert !user.announcements
    assert !user.sunlight_announcements

    assert_equal 1, user.interests.count
    interest = user.interests.first

    assert_equal "item", interest.interest_type
    assert_equal item_type, interest.item_type
    assert_equal item_id, interest.in
    assert_equal "sms", interest.notifications
    assert_not_nil interest.data['bill_id'] # loaded from fixture
  end

  def test_subscribe_by_sms_with_taken_phone_number_creates_new_interest_but_not_new_account
    # use an intentionally non-standard phone number, to make sure the matching works
    phone = "5555551212"
    item_id = "hr4192-112"
    item_type = "bill"

    user = create :user, :phone => phone # confirmation doesn't matter
    assert user.confirmed?

    mock_item item_id, item_type

    count = User.count
    assert_equal 0, user.interests.count

    # SMS should not be sent
    Admin.should_not_receive(:new_user)
    SMS.should_not_receive(:deliver!).with("Remote Subscription", phone, anything)

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 200

    user.reload
    assert_equal count, User.count
    assert_equal 1, user.interests.count
    assert user.confirmed? # still got it

    interest = user.interests.first

    assert_equal "item", interest.interest_type
    assert_equal item_type, interest.item_type
    assert_equal item_id, interest.in
    assert_equal "sms", interest.notifications
    assert_not_nil interest.data['bill_id'] # loaded from fixture

    # verify *no* SMS was sent to user, not needed
    #TODO
  end

  def test_subscribe_by_sms_with_blank_phone_number_fails
    phone = ""
    item_id = "hr4192-112"
    item_type = "bill"

    mock_item item_id, item_type

    assert_nil User.where(:phone => phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 500
    assert_nil User.where(:phone => phone).first
  end

  def test_subscribe_by_sms_with_invalid_interest_details_fails
    # test on 'interest_type', 'item_type', 'item_id'
    phone = "+15555551212"
    item_id = "hr4192-112"
    item_type = "bill"

    assert_nil User.where(:phone => phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => "", :item_type => item_type,
      :source => "testing"
    }
    assert_response 500
    assert_nil User.where(:phone => phone).first

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 500
    assert_nil User.where(:phone => phone).first


    # relaxed until COC team can update their end

    # post "/remote/subscribe/sms", {
    #   :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => "",
    #   :source => "testing"
    # }
    # assert_response 500
    # assert_nil User.where(:phone => phone).first
  end

  def test_subscribe_by_sms_when_remote_item_doesnt_exist_fails
    phone = "+15555551212"
    item_id = "hr4195-112" # no fixture for this
    item_type = "bill"

    mock_item item_id, item_type # should mock it to return nil

    assert_nil User.where(:phone => phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 500
  end

  def test_subscribe_by_sms_with_invalid_credentials_fails
  end


  def test_receive_confirm
    phone = "+15555551212"
    user = create :phone_user

    assert !user.confirmed?
    assert !user.phone_confirmed?
    current_pass = user.password_hash
    assert user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => phone
    }
    assert_response 200

    user.reload
    assert user.confirmed?
    assert user.phone_confirmed?
    assert_not_equal current_pass, user.password_hash
    assert user.should_change_password
    # SMS should also have been sent with the user's password
  end

  def test_receive_confirm_with_no_phone_or_body
    phone = "+15555551212"
    user = create :phone_user

    assert !user.confirmed?
    assert !user.phone_confirmed?
    current_pass = user.password_hash
    assert user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => ""
    }
    assert_response 500

    user.reload
    assert !user.confirmed?
    assert !user.phone_confirmed?

    post "/remote/twilio/receive", {
      "Body" => "",
      "From" => phone
    }
    assert_response 500

    user.reload
    assert !user.confirmed?
    assert !user.phone_confirmed?
  end

  def test_receive_confirm_from_unknown_phone
    phone = "+15555551212"
    user = create :phone_user, :phone => phone.succ

    assert_nil User.by_phone(phone)

    assert !user.confirmed?
    assert !user.phone_confirmed?
    current_pass = user.password_hash
    assert user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => phone
    }
    assert_response 404

    user.reload
    assert !user.confirmed?
    assert !user.phone_confirmed?
  end

  def test_receive_confirm_from_phone_that_has_existing_confirmed_account
    phone = "+15555551212"
    user = create :user, :phone => phone, :phone_confirmed => true

    assert user.phone_confirmed?
    assert user.confirmed?
    current_pass = user.password_hash
    assert !user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => phone
    }
    assert_response 200

    user.reload
    assert user.confirmed?
    assert user.phone_confirmed?
    assert_equal current_pass, user.password_hash
    assert !user.should_change_password
  end


end