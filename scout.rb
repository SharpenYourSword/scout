#!/usr/bin/env ruby

require 'config/environment'
require 'sinatra/content_for'
require 'sinatra/flash'

set :logging, false
set :views, 'views'
set :public_folder, 'public'

# disable sessions in test environment so it can be manually set
set :sessions, !test?
set :session_secret, config[:session_secret]

configure(:development) do |config|
  require 'sinatra/reloader'
  config.also_reload "config/environment.rb"
  config.also_reload "config/admin.rb"
  config.also_reload "config/email.rb"
  config.also_reload "helpers.rb"
  config.also_reload "models/*.rb"
  config.also_reload "subscriptions/adapters/*.rb"
  config.also_reload "subscriptions/*.rb"
  config.also_reload "deliveries/*.rb"
end


# routes

before do
  @new_user = logged_in? ? nil : User.new
  @interests = user_interests
end

get '/' do
  erb :index
end

post '/users' do
  @new_user = User.new params[:user]

  unless @new_user.password.present? and @new_user.password_confirmation.present?
    flash[:password] = "Can't use a blank password."
    redirect_home and return
  end

  if @new_user.save
    log_in @new_user

    flash[:success] = "Your account has been created. Scout at will."
    redirect_home
  else
    erb :index
  end
end

put '/user/password' do
  requires_login

  unless User.authenticate(current_user, params[:old_password])
    flash[:password] = "Incorrect current password."
    redirect_home and return
  end

  unless params[:password].present? and params[:password_confirmation].present?
    flash[:password] = "Can't use a blank password."
    redirect_home and return
  end

  current_user.password = params[:password]
  current_user.password_confirmation = params[:password_confirmation]
  current_user.should_change_password = false

  if current_user.save
    flash[:password] = "Your password has been changed."
    redirect_home
  else
    erb :index
  end

end

post '/login' do
  unless params[:email] and user = User.where(:email => params[:email]).first
    flash[:user] = "No account found by that email."
    redirect_home and return
  end

  if User.authenticate(user, params[:password])
    log_in user
    redirect_home
  else
    flash.now[:user] = "Invalid password."
    erb :index
  end

end

post '/login/forgot' do
  unless params[:email] and user = User.where(:email => params[:email].strip).first
    flash[:forgot] = "No account found by that email."
    redirect_home and return
  end

  # issue a new reset token
  user.new_reset_token

  # email the user with a link including the token
  subject = "Request to reset your password"
  body = erb :"account/mail/reset_password", :layout => false, :locals => {:user => user}

  unless user.save and Email.deliver!("Password Reset Request", user.email, subject, body)
    flash[:forgot] = "Your account was found, but there was an error actually sending the reset password email. Try again later, or write us and we can try to figure out what happened."
    redirect_home and return
  end

  flash[:forgot] = "We've sent an email to reset your password."
  redirect_home
end

get '/account/reset' do
  unless params[:reset_token] and user = User.where(:reset_token => params[:reset_token]).first
    halt 404 and return
  end

  # reset the password itself, and the token
  new_password = user.reset_password
  user.new_reset_token
  unless user.save
    flash[:forgot] = "There was an error issuing you a new password. Please contact us for support."
    redirect_home and return
  end

  # send the next email with the new password

  subject = "Your password has been reset"
  body = erb :"account/mail/new_password", :layout => false, :locals => {:new_password => new_password}

  unless Email.deliver!("Password Reset", user.email, subject, body)
    flash[:forgot] = "There was an error emailing you a new password. Please contact us for support."
    redirect_home and return
  end

  flash[:forgot] = "Your password has been reset, and a new one has been emailed to you."
  redirect_home
end

put '/user' do
  requires_login
  
  current_user.attributes = params[:user]

  # current_user["phone"] = params[:phone]
  # current_user["delivery"]["mechanism"] = params[:mechanism]
  # current_user["delivery"]["email_frequency"] = params[:email_frequency]
  
  if current_user.save
    halt 200
  else
    status 500
    headers["Content-Type"] = "application/json"
    {
      :error => current_user.errors.full_messages.first
    }.to_json
  end
end

get '/logout' do
  log_out if logged_in?
  redirect '/'
end

get '/search/:interest' do
  interest_in = params[:interest].gsub("\"", "")
  sorted_types = search_data.sort_by {|k, v| v[:order]}

  erb :search, :layout => !pjax?, :locals => {
    :types => sorted_types,
    :interest_in => interest_in
  }
end

# landing page for item
# get '/:interest_type/:item_id'
get(/^\/(#{interest_data.keys.join '|'})\/([^\/]+)\/?/) do
  interest_type = params[:captures][0]
  item_id = params[:captures][1]

  interest = nil
  if logged_in?
    interest = current_user.interests.where(:in => item_id, :interest_type => interest_type).first
  end

  erb :show, :layout => !pjax?, :locals => {
    :interest_type => interest_type, 
    :item_id => item_id, 
    :interest => interest
  }
end

# actual JSON data for item
# get '/:find/:interest_type/:item_id' 
get(/^\/find\/(#{interest_data.keys.join '|'})\/([^\/]+)$/) do
  interest_type = params[:captures][0]
  item_id = params[:captures][1]
  subscription_type = interest_data[interest_type][:adapter]

  unless item = Subscriptions::Manager.find(subscription_type, item_id)
    halt 404 and return
  end

  html = erb :"subscriptions/#{subscription_type}/_show", :layout => false, :locals => {
    :interest_type => interest_type, 
    :item => item
  }

  headers["Content-Type"] = "application/json"
  {
    :html => html,
    :item_url => item.find_url
  }.to_json
end

post '/interest/track' do
  requires_login

  interest_type = params[:interest_type]
  item_id = URI.decode params[:item_id] # can possibly have spaces, decode first
  
  unless item = Subscriptions::Manager.find(interest_data[interest_type][:adapter], item_id)
    halt 404 and return
  end

  interest = current_user.interests.new :interest_type => interest_type, :in => item_id, :data => item.data

  subscriptions = interest_data[interest_type][:subscriptions].keys.map do |subscription_type|
    current_user.subscriptions.new :interest_in => item_id, :subscription_type => subscription_type
  end

  if interest.valid? and (subscriptions.reject {|s| s.valid?}.empty?)
    interest.save!
    subscriptions.each do |subscription|
      subscription[:interest_id] = interest.id
      subscription.save!
    end

    headers["Content-Type"] = "application/json"
    {
      :interest_id => interest.id.to_s,
      :pane => partial("partials/interest", :engine => "erb", :locals => {:interest => interest})
    }.to_json
  else
    halt 500
  end
end

get "/account/:id.rss" do
  unless user = User.where(:_id => BSON::ObjectId(params[:id])).first
    halt 404 and return
  end

  page = (params[:page] || 1).to_i
  page = 1 if page <= 0 or page > 200000000
  per_page = 100

  items = SeenItem.where(:user_id => user.id).desc(:date)
  items = items.skip(per_page * (page - 1)).limit(per_page)

  headers["Content-Type"] = "application/rss+xml"
  erb :"rss/user", :layout => false, :locals => {
    :items => items,
    :url => request.url
  }
end

get /\/interest\/([\w\d]+)\.?(\w+)?$/ do |interest_id, ext|
  # do not require login
  # for RSS, want readers and bots to access it freely
  # for SMS, want users on phones to see items easily without logging in
  # for JSON, no need to require an API key for now

  unless ['rss', 'json', nil, ''].include?(ext)
    halt 404 and return
  end

  unless interest = Interest.find(interest_id.strip)
    halt 404 and return
  end

  # handle JSON completely separately
  if ext == 'json'
    return json_for interest, params
  end
  
  page = (params[:page] || 1).to_i
  page = 1 if page <= 0 or page > 200000000
  per_page = (ext == 'rss') ? 100 : 20

  items = SeenItem.where(:interest_id => interest.id).desc(:date)
  items = items.skip(per_page * (page - 1)).limit(per_page)

  if ext == 'rss'
    headers["Content-Type"] = "application/rss+xml"
    erb :"rss/interest", :layout => false, :locals => {
      :items => items, 
      :interest => interest,
      :url => request.url
    }

  # HTML version only works if the interest is a keyword search
  else 
    erb :"sms", :locals => {
      :items => items,
      :interest => interest
    }
  end
end

delete '/interest/untrack' do
  requires_login

  unless interest = current_user.interests.where(:_id => BSON::ObjectId(params[:interest_id].strip)).first
    halt 404 and return
  end

  subscriptions = interest.subscriptions.to_a
    
  interest.destroy
  subscriptions.each do |subscription| 
    subscription.destroy
  end
  
  halt 200
end

post '/subscriptions' do
  requires_login

  phrase = params[:interest].strip
  subscription_type = params[:subscription_type]

  new_interest = false

  # if this is editing an existing one, find it
  if params[:interest_id].present?
    interest = current_user.interests.find params[:interest_id]
  end

  # default to a new one
  if interest.nil?
    interest = current_user.interests.new :in => phrase, :interest_type => "search"
    new_interest = true
  end
  
  subscription = current_user.subscriptions.new(
    :interest_in => phrase, 
    :subscription_type => subscription_type
  )

  if params[:subscription_data]
    subscription.data = params[:subscription_data]
  end
  
  headers["Content-Type"] = "application/json"

  # make sure interest has the same validations as subscriptions
  if interest.valid? and subscription.valid?
    interest.save!
    subscription[:interest_id] = interest.id
    subscription.save!
    
    {
      :interest_id => interest.id.to_s,
      :subscription_id => subscription.id.to_s,
      :new_interest => new_interest,
      :pane => partial("partials/interest", :engine => "erb", :locals => {:interest => interest})
    }.to_json
  else
    halt 500
  end
  
end

get '/items/:interest/:subscription_type' do
  interest_in = params[:interest].strip
  subscription_type = params[:subscription_type]

  params[:subscription_data] ||= {} # must default to empty hash

  # make new, temporary subscription items
  results = Subscription.new(
    :interest_in => interest_in,
    :subscription_type => params[:subscription_type],
    :data => params[:subscription_data]
  ).search(:page => (params[:page] ? params[:page].to_i : 1))
    
  # if results is nil, it usually indicates an error in one of the remote services -
  # this would be where to catch it and display something
  if results.nil?
    puts "[#{subscription_type}][#{interest_in}][search] ERROR while loading this"
  end
  
  if results
    results = results.sort {|a, b| b.date <=> a.date}
  end
  
  html = erb :items, :layout => false, :locals => {
    :items => results, 
    :subscription_type => subscription_type,
    :interest_in => interest_in
  }

  headers["Content-Type"] = "application/json"
  
  count = results ? results.size : -1
  {
    :count => count,
    :description => "#{search_data[params[:subscription_type]][:search]} matching \"#{interest_in}\"",
    :html => html,
    :search_url => (count > 0 ? results.first.search_url : nil)
  }.to_json
end

# delete the subscription, and, if it's the last subscription under the interest, delete the interest
delete '/subscription/:id' do
  requires_login

  if subscription = Subscription.where(:user_id => current_user.id, :_id => BSON::ObjectId(params[:id].strip)).first
    halt 404 unless interest = Interest.where(:user_id => current_user.id, :_id => subscription.interest_id).first

    deleted_interest = false

    if interest.subscriptions.count == 1
      interest.destroy
      deleted_interest = true
    end

    subscription.destroy

    pane = deleted_interest ? nil : partial("partials/interest", :engine => "erb", :locals => {:interest => interest})

    headers["Content-Type"] = "application/json"
    {
      :deleted_interest => deleted_interest,
      :interest_id => interest.id.to_s,
      :pane => pane
    }.to_json
  else
    halt 404
  end
end

delete '/interest/:id' do
  requires_login
  
  if interest = current_user.interests.where(:_id => BSON::ObjectId(params[:id].strip)).first
    subscriptions = interest.subscriptions.to_a
    
    interest.destroy
    subscriptions.each do |subscription|
      subscription.destroy
    end
    
    halt 200
  else
    halt 404
  end
end


# auth helpers

helpers do

  def pjax?
    (request.env['HTTP_X_PJAX'] or params[:_pjax]) ? true : false
  end

  def user_interests
    logged_in? ? current_user.interests.desc(:created_at).all.map {|k| [k, k.subscriptions]} : []
  end

  def logged_in?
    !current_user.nil?
  end
  
  def current_user
    @current_user ||= User.where(:email => session['user_email']).first
  end

  def redirect_home
    redirect(params[:redirect] || '/')
  end
  
  def log_in(user)
    session['user_email'] = user.email
  end
  
  def log_out
    session['user_email'] = nil
  end
  
  def requires_login
    redirect '/' unless logged_in?
  end
end

helpers do
  
  def json(results, params)
    response['Content-Type'] = 'application/json'
    json = results.to_json
    params[:callback].present? ? "#{params[:callback]}(#{json});" : json
  end

  def json_for(interest, params) 
    # hide some fields for JSON feeds
    # items = items.only SeenItem.public_json_fields
    subscriptions = Subscription.where(:interest_id => interest.id)
    subscriptions = subscriptions.only(Subscription.public_json_fields)

    interest = Interest.where(:_id => interest.id).only(Interest.public_json_fields).first
    
    items = SeenItem.where(:interest_id => interest.id).desc(:date)
    items = items.only(SeenItem.public_json_fields)
    count = items.count

    pagination = pagination_for params
    skip = pagination[:per_page] * (pagination[:page]-1)
    limit = pagination[:per_page]
    items = items.skip(skip).limit(limit)

    items = items.to_a

    results = {
      :results => items.map {|item| clean_document item},
      :count => count,
      :page => {
        :count => items.size,
        :per_page => pagination[:per_page],
        :page => pagination[:page]
      },
      :interest => clean_document(interest).merge(
        :subscriptions => subscriptions.map {|sub| clean_document sub}
      )
    }

    json results, params
  end

  def clean_document(item)
    attrs = item.attributes
    attrs.delete "_id"
    attrs
  end

  def pagination_for(params)
    default_per_page = 50
    max_per_page = 50
    max_page = 200000000 # let's keep it realistic
    
    # rein in per_page to somewhere between 1 and the max
    per_page = (params[:per_page] || default_per_page).to_i
    per_page = default_per_page if per_page <= 0
    per_page = max_per_page if per_page > max_per_page
    
    # valid page number, please
    page = (params[:page] || 1).to_i
    page = 1 if page <= 0 or page > max_page
    
    {:per_page => per_page, :page => page}
  end

end