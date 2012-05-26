class Tag
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :user

  field :name
  field :public, type: Boolean, default: false
  field :description

  validates_uniqueness_of :name, :scope => :user_id
  
  scope :public, where(:public => true)
  default_scope desc(:created_at)

  # not a formal relationship, depends on interests keeping their own tag array
  def interests
    user.interests.where :tags => name
  end

  def private?
    !public?
  end

  def self.normalize(tag)
    tag.gsub(/[^\w\d\s]/, '').gsub(/\s{2,}/, ' ').downcase
  end

  def self.slugify(tag)
    tag.tr ' ', '-'
  end

  def self.deslugify(tag)
    tag.tr '-', ' '
  end
end