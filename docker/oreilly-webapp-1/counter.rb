# ruby imports
require 'sinatra'
require 'redis'

# tell sinatra to bind to 0.0.0.0, which will bind to all network interfaces.
# important to do this in container so we can access outside localhost
set :bind, '0.0.0.0'

# instantiate connection to redis, using hostname redis (name of container we started with)
# going to use a docker link to connect the two containers.
# docker links allows us to use container name, which is simpler than using the env variables
configure do
    $redis = Redis.new(:host => 'redis')
end

# get with root path, this will be executed when we access root of app in browser, or http get req.
get '/' do
    count = $redis.incr('count')

    "<h1>Hello there!</h1>"\
    "<p>This page has been viewed #{count} times</p>"
end