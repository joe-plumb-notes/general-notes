FROM ubuntu
MAINTAINER joeplumb <hello@joeplumb.com>
RUN apt-get update && apt-get install -y \
    ruby \
    ruby-json
RUN gem install sinatra --no-ri --no-rdoc
RUN gem install redis --no-ri --no-rdoc
ADD counter.rb counter.rb
EXPOSE 4567
ENTRYPOINT [ "ruby", "counter.rb" ]