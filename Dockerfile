FROM alpine:latest

ADD . /root
RUN /root/build.sh
