FROM ruby:2.3
RUN apt-get update -qq && apt-get install -y build-essential

ENV LANG C.UTF-8
ENV LANGUAGE C.UTF-8
ENV LC_ALL C.UTF-8

WORKDIR /myapp/src
ADD src/CRF++-0.58.tar.gz CRF++-0.58
ADD src/install_crfpp.sh install_crfpp.sh
RUN bash install_crfpp.sh
WORKDIR /myapp
ADD Gemfile Gemfile
ADD . /myapp
RUN bundle install

CMD ["rackup", "--host", "0.0.0.0"]
