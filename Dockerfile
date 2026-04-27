FROM openresty/openresty:alpine-fat

ARG SITE_PORT
ARG SITE_HOST
ARG TLS_MODE
ARG SUB
ARG SERVERS

ENV SITE_PORT=${SITE_PORT}
ENV SITE_HOST=${SITE_HOST}
ENV TLS_MODE=${TLS_MODE}
ENV SUB=${SUB}
ENV SERVERS=${SERVERS}

EXPOSE ${SITE_PORT}

RUN rm /usr/local/openresty/nginx/conf/nginx.conf

COPY nginx.conf.esh /usr/local/openresty/nginx/conf/

RUN apk add --no-cache esh
RUN luarocks install lua-resty-http

COPY config_fetcher.lua /etc/nginx/lua/

CMD ["/bin/sh", "-c", "esh -o /usr/local/openresty/nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf.esh && exec nginx -g 'daemon off;'"]
