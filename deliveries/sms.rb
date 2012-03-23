require 'twilio-rb'

module Deliveries
  module SMS

    def self.deliver_for_user!(user)
      failures = 0
      successes = []

      email = user.email
      phone = user.phone
      interests = user.interests.all

      unless user.phone.present?
        Admin.report Report.failure("Delivery", "User is signed up for SMS alerts but has no phone #{email}", :email => email)
        return 0
      end

      interests.each do |interest|
        deliveries = Delivery.where(:interest_id => interest.id, :user_id => user.id).all.to_a
        next unless deliveries.any?
        
        core = render_interest interest, deliveries
        content = render_final core

        if content.size > 160
          too_big = content.size - 160
          original = content.dup
          # cut out the overage, plus 3 for the ellipse, one for the potential quote, 3 for an additional buffer
          truncated_core = core[0...-(too_big + 3 + 1 + 3)] + "..." + (interest.search? ? "\"" : "")
          content = render_final truncated_core

          # I may disable the emailing of this report after a while, but I want to see the frequency of this in practice
          Admin.report Report.warning("Delivery", "SMS more than 160 characters, truncating", :truncation => true, :original => content, :truncated => content)
        end

        if content.size > 160
          Admin.report Report.failure("Delivery", "Failed somehow to truncate SMS to less than 160", :truncation => true, :original => original, :truncated => content)
          next
        end

        if sms_user email, phone, content
          deliveries.each &:delete
          successes << save_receipt!(user, deliveries, content)
        else
          failures += 1
        end
      end

      if failures > 0
        Admin.report Report.failure("Delivery", "Failed to deliver #{failures} SMSes to #{email}")
      end

      if successes.any?
        Report.success("Delivery", "Delivered #{successes.size} SMSes to #{email}")
      end

      successes
    end

    def self.render_interest(interest, deliveries)
      grouped = deliveries.group_by &:subscription

      content = "new "

      content << grouped.keys.map do |subscription|
        subscription.adapter.short_name grouped[subscription].size, subscription, interest
      end.join(", ")

      content << " on "

      if interest.search?
        content << "\"#{interest.in}\""
      else
        content << Subscription.adapter_for(interest_data[interest.interest_type][:adapter]).interest_name(interest)
      end

      content
    end

    def self.render_final(content)
      "[Scout] #{content} http://scout.sunlightfoundation.com"
    end

    def self.save_receipt!(user, deliveries, content)
      Receipt.create!(
        :frequency => "immediate",
        :mechanism => "sms",

        :deliveries => deliveries.map {|delivery| delivery.attributes.dup},

        :user_email => user.email,
        :user_delivery => user.delivery,

        :content => content,
        :delivered_at => Time.now
      )
    end

    # the actual mechanics of sending the email
    def self.sms_user(email, phone, content)
      if config[:twilio][:from].present?
        begin
          Twilio::SMS.create :to => phone, :from => config[:twilio][:from], :body => content
          true
        rescue Twilio::ConfigurationError, Twilio::InvalidStateError, Twilio::APIError
          false
        end
      else
        puts "\n[SMS USER] Would have delivered this to #{phone} (#{email}):"
        puts "\n#{content}"
        true # if no 'from' number is specified, we'll assume it's a dev environment or something
      end
    end

  end
end