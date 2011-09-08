class Subscription
  include Mongoid::Document
  include Mongoid::Timestamps
  
  field :subscription_type
  field :initialized, :type => Boolean, :default => false
  field :latest_time, :type => Time
  field :keyword
    
  index :subscription_type
  index :initialized
  index :user_id
  index :keyword
  
  has_many :seen_ids
  has_many :deliveries
  belongs_to :user
  
  validates_presence_of :user_id
  validates_presence_of :subscription_type
  
  # will eventually refer to individual subscription type's validation method
  validate do
    if keyword.blank?
      errors.add(:base, "Enter a keyword or phrase to subscribe to.")
    end
  end
  
  scope :initialized, :where => {:initialized => true}
  scope :uninitialized, :where => {:initialized => false}
  
  # adapter class associated with a particular subscription
  def adapter
    "Subscriptions::Adapters::#{subscription_type.camelize}".constantize rescue nil
  end
  
  after_create :initial_poll
  def initial_poll
    Subscriptions::Manager.initialize! self
  end
end