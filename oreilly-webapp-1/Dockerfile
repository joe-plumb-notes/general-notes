FROM alpine
MAINTAINER joeplumb <hello@joeplumb.com>
RUN apk update && apk add ruby && apk add ruby-json
RUN gem install sinatra --no-ri --no-rdoc
RUN gem install redis --no-ri --no-rdoc
ADD counter.rb counter.rb
EXPOSE 4567
ENTRYPOINT [ "ruby", "counter.rb" ]