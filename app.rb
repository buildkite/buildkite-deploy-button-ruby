require 'sinatra'
require 'json'
require 'faraday'
require 'rack/parser'
require 'rack/ssl-enforcer'

# Required
set :project_name, ENV['PROJECT_NAME'] || raise("no PROJECT_NAME set")
set :branch_name, ENV['BRANCH_NAME'] || raise("no BRANCH_NAME set")
set :secret, ENV['SECRET'] || raise("no SECRET set")
set :session_secret, ENV['SESSION_SECRET'] || raise("no SESSION_SECRET set")
set :buildkite_access_token, ENV['BUILDKITE_ACCESS_TOKEN'] || raise("no BUILDKITE_ACCESS_TOKEN set")

# Optional
set :buildkite_api_host, ENV['BUILDKITE_API_HOST'] || 'https://api.buildkite.com'

# SSL redirecter - must be the first piece of middleware
use Rack::SslEnforcer unless development?

# JSON request body parsing
use Rack::Parser

# Basic auth
use(Rack::Auth::Basic, "Restricted Area") {|u, p| u == settings.secret and p == ''}

# CSRF protection
enable :sessions
set :protection, use: [:authenticity_token]

# State
unblockable_job = nil

helpers do
  def buildkite_api
    Faraday.new(url: settings.buildkite_api_host) do |faraday|
      faraday.authorization :Bearer, settings.buildkite_access_token
      faraday.request :url_encoded
      # faraday.response :logger
      faraday.adapter Faraday.default_adapter
      faraday.use Faraday::Response::RaiseError
    end
  end
end

post "/" do
  halt(401, 'Looks like you forgot to add ?secret=the-secret') if params[:secret].nil?
  halt(401, 'Secret is incorrect') if params[:secret] != settings.secret

  event = JSON.parse(request.body.read)
  puts event.inspect # helpful for inspecting incoming webhook requests

  is_matching_build_request =
    request.env["HTTP_X_BUILDKITE_EVENT"] == "build" &&
     event['build']['project']['name'] == settings.project_name &&
     event['build']['branch'] == settings.branch_name

  if is_matching_build_request
    unblockable_job = build['jobs'].find {|job| job['unblockable']}
  end

  status 200
end

get "/" do
  erb :button
end

# Is it unblockable?
get "/unblockable" do
  if unblockable_job
    200
  else
    412
  end
end

# Unblock the job
post "/unblock" do
  if unblockable_job
    buildkite_api.post unblockable_job['unblock_url']
    200
  else
    412
  end
end
