# API key management
# We sync with the central API key service to figure out which users are developers, based on email


# Verify that posts to API key management endpoints are verified

before /^\/services\// do
  unless SunlightServices.verify params, Environment.config['services']['shared_secret'], Environment.config['services']['api_name']
    Admin.report Report.failure(
      "API Key Signature Check", "Bad signature", 
      key: params[:key], email: params[:email], status: params[:status],
      ip: request.ip
    )
    halt 403, 'Bad signature' 
  end
end



# API key management endpoints

post '/services/replicate_key/:key/' do
  unless params[:key].present? and params[:status].present? and params[:email].present?
    Admin.report Report.failure(
      "Replicate Key", "Could not replicate key, not enough information", 
      key: params[:key], email: params[:email], status: params[:status],
      ip: request.ip
    )

    halt 403, "Missing a key, email, and/or status: #{params.inspect}"
  end

  key = ApiKey.find_or_create_by key: params[:key]
  key.email = params[:email]
  key.status = params[:status]
  key.save!
end


post '/services/create_key/' do
  begin
    ApiKey.create! key: params[:key],
        email: params[:email],
        status: params[:status]
  rescue
    Admin.report Report.failure(
      "Create Key", "Could not create key, duplicate key or email", 
      key: params[:key], email: params[:email], status: params[:status],
      ip: request.ip
    )
    halt 403, "Could not create key, duplicate key or email"
  end
end

post '/services/update_key/' do
  if key = ApiKey.where(:key => params[:key]).first
    begin
      key.attributes = {:email => params[:email], :status => params[:status]}
      key.save!
    rescue
      Admin.report Report.failure(
        "Update Key", "Could not update key, errors: #{key.errors.full_messages.join ', '}",
        key: params[:key], email: params[:email], status: params[:status],
        ip: request.ip
      )
      halt 403, "Could not update key, errors: #{key.errors.full_messages.join ', '}"
    end
  else
    Admin.report Report.failure(
      "Update Key", 'Could not locate API key by the given key',
      key: params[:key], email: params[:email], status: params[:status],
      ip: request.ip
    )
    halt 404, 'Could not locate API key by the given key'
  end
end

post '/services/update_key_by_email/' do
  if key = ApiKey.where(:email => params[:email]).first
    begin
      key.attributes = {:key => params[:key], :status => params[:status]}
      key.save!
    rescue
      Admin.report Report.failure(
        "Update Key by Email", "Could not update key, errors: #{key.errors.full_messages.join ', '}",
        key: params[:key], email: params[:email], status: params[:status],
        ip: request.ip
      )
      halt 403, "Could not update key, errors: #{key.errors.full_messages.join ', '}"
    end
  else
    Admin.report Report.failure(
      "Update Key by Email", 'Could not locate API key by the given key',
      key: params[:key], email: params[:email], status: params[:status],
      ip: request.ip
    )
    halt 404, 'Could not locate API key by the given email'
  end
end



# SunlightServices helper class

require 'cgi'
require 'hmac-sha1'
require 'net/http'

class SunlightServices
  
  def self.verify(params, shared_secret, api_name)
    return false unless params[:email] and params[:status]
    return false unless params[:api] == api_name
    
    given_signature = params.delete 'signature'
    signature = signature_for params, shared_secret
    
    signature == given_signature
  end

  def self.signature_for(params, shared_secret)
    HMAC::SHA1.hexdigest shared_secret, signature_string(params)
  end

  def self.signature_string(params)
    params.keys.map(&:to_s).sort.map do |key|
      "#{key}=#{CGI.escape((params[key] || params[key.to_sym]).to_s)}"
    end.join '&'
  end
end