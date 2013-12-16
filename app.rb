require 'sinatra'
require 'json'
require 'redis'
require 'uri'

set :bind, "0.0.0.0"
set :session_secret, ENV["SESSION_SECRET"]
enable :sessions

post '/cloud-event/register' do
  address, name, location, timezone = params.values_at(:address, :name, :location, :timezone)

  device = {
    'address' => address,
    'name' => name,
    'location' => location,
    'timezone' => timezone
  }
  db.hset('devices', address, JSON.dump(device))

  204
end

post '/cloud-event/deregister' do
  address, name = params.values_at(:address, :name)

  db.hdel('devices', address)

  204
end

post '/cloud-event/announce' do
  address, version = params.values_at(:address, :version)

  device = JSON.parse(db.hget('devices', address) || '{}')
  device.merge!(:version => version)
  db.hset('devices', address, JSON.dump(device))

  204
end

post '/cloud-event/add-owner' do
  address, name, email = params.values_at(:address, :name, :email)

  user = {
    'name' => name,
    'email' => email
  }
  db.hset('users', email, JSON.dump(user))
  db.sadd("ownerships:#{address}", email)

  204
end

post '/cloud-event/remove-owner' do
  address, name, email = params.values_at(:address, :name, :email)

  user = {
    'name' => name,
    'email' => email
  }
  db.srem("ownerships:#{address}", email)

  204
end

post '/device-event/counter-changed' do
  address, name, format, payload = params.values_at(:address, :name, :format, :payload)
  title, value = JSON.parse(payload)

  db.hset('counters', address, value)

  204
end

get '/' do
  erb :index, :locals => { :page => 'counters' }
end

get '/goto' do
  address = params[:address]
  if db.hexists('devices', address)
    redirect "/#{address}/counter"
  else
    erb :goto, :locals => { :address => address }
  end
end

get '/:address/counter' do |address|
  erb :counter, :locals => { :device => Device.new(db, address) }
end

get '/:address/counter.json' do |address|
  content_type :json
  Device.new(db, address).to_json
end

helpers do

  def redis_url
    @redis_url ||= URI.parse(ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
  end

  def db
    @db ||= Redis.new(:host => redis_url.host,
      :port => redis_url.port,
      :user => redis_url.user,
      :password => redis_url.password)
  end

  def counters
    db.hgetall('counters')
  end

end

class Device
  attr_accessor :db, :address

  def initialize(db, address)
    @db, @address = db, address
  end

  def counter
    db.hget('counters', address).to_i
  end

  def info
    @info ||= JSON.parse(db.hget('devices', address))
  end

  def to_json
    info.merge("counter" => counter).to_json
  end

  %w[name location timezone version].each do |val|
    define_method(val) do
      info[val]
    end
  end
end
