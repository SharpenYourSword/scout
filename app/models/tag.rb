class Tag
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :user

  field :name
  field :public, type: Boolean, default: false
  field :description

  index :name
  index :public

  validates_uniqueness_of :name, :scope => :user_id
  
  default_scope desc(:created_at)

  scope :for_time, ->(start, ending) {where(created_at: {"$gt" => Time.parse(start).midnight, "$lt" => Time.parse(ending).midnight + 1.day})}

  # not a formal relationship, depends on interests keeping their own tag array
  def interests
    user.interests.where :tags => name
  end

  after_destroy :remove_from_interests
  def remove_from_interests
    interests.each do |interest|
      interest.pull :tags, name
    end
  end

  def private?
    !public?
  end

  def self.normalize(name)
    name.gsub(/[^\w\d\s]/, '').gsub(/\s{2,}/, ' ').strip.downcase
  end

  def self.slugify(name)
    name.strip.tr ' ', '-'
  end

  def self.deslugify(name)
    name.strip.tr '-', ' '
  end
end