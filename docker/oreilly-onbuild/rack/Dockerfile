# Start with base ruby image
FROM ruby
# Expose port 4567 so we can map to the docker host
EXPOSE 4567
# Entrypoint assumes we have a rack application - a common way to run a 
# ruby application, so running this will run rackup against the config.ru file.
ENTRYPOINT ["bundle", "exec", "rackup", "-p", "4567", "--host", "0.0.0.0"]
# These will be executed by any files that use this image as a base
# Add all file in the docker context to the root dir in the image
ONBUILD ADD . /
# installs ruby dependencies installed in the gem file (assumes gem file in root of your project)
ONBUILD RUN bundle install