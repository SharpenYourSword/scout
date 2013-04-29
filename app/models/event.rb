class Event
  include Mongoid::Document
  include Mongoid::Timestamps

  field :type
  field :description
  field :data, type: Hash

  index type: 1

  # for looking up email clicks
  index({type: 1, item_type: 1})

  scope :for_time, ->(start, ending) {where(created_at: {"$gt" => Time.zone.parse(start).midnight, "$lt" => Time.zone.parse(ending).midnight})}

  # log a visit to the redirector
  def self.email_click!(data = {})
    create!({
      type: "email-click"
    }.merge(data))
  end

  def self.remove_alert!(interest)
    create!(
      type: "remove-alert", 
      description: "#{interest.user.contact} from #{interest.in}", 
      data: interest.attributes.dup
    )
  end

  def self.unsubscribe!(user, old_info, description = nil)
    create!(
      type: "unsubscribe",
      contact: user.contact,
      description: (description || "One-click unsubscribe from #{user.contact}"),
      data: old_info
    )
  end

  def self.postmark_failed!(tag, to, subject, body)
    create!(
      type: "postmark-failed",
      description: "Postmark down, SMTP succeeded",
      data: {
        tag: tag, to: to, subject: subject, body: body
      }
    )
  end

  def self.email_failed!(tag, to, subject, body)
    create!(
      type: "email-failed",
      description: "Postmark down, SMTP failed also",
      data: {
        tag: tag, to: to, subject: subject, body: body
      }
    )
  end

  def self.postmark_bounce!(email, bounce_type, details)
    user = User.where(email: email).first

    stop = %w{ SpamComplaint SpamNotification BadEmailAddress Blocked }
    unsubscribed = false
    if stop.include?(bounce_type)
      unsubscribed = true
      if user
        user.notifications = "none"
        user.save!
      end
    end

    event = create!(
      type: "postmark-bounce",
      description: "#{bounce_type} for #{email}",
      data: details,
      user_id: user ? user.id : nil,
      unsubscribed: unsubscribed
    )

    # email admin
    Admin.bounce_report event.description, event.attributes.dup
  end

  def self.blocked_email!(email, service)
    event = create!(
      type: "blocked-email",
      description: "Blocked #{email} from logging in with their account because it came from #{service} :(",
      email: email,
      service: service
    )

    Admin.report Report.warning("Login", "Blocked login from #{email}, frowny face", event.attributes.dup)
  end

  def self.google_crawling!(item_id, item_type)
    if item = Item.where(item_id: item_id, item_type: item_type).first
      time = Time.now
      item.google_hits << time
      item.last_google_hit = time
      item.save!
    end
  end
end