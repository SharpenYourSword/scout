# This class is meant to affect the UI *only*, and shouldn't need to appear in subscription logic. 
# Relevant keyword-wide fields should be duplicated from Keyword to Subscription.
class Keyword
  include Mongoid::Document
  include Mongoid::Timestamps
  
  field :keyword
  field :keyword_type
  field :keyword_name # display name, for non-keyword subscriptions
  field :keyword_item, :type => Hash # holds metadata about the item being subscribed to
  
  index :keyword
  index :user_id
  index :keyword_type
  
  validates_presence_of :user_id
  validates_presence_of :keyword
  
  belongs_to :user
  has_many :subscriptions
end