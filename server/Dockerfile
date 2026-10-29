# syntax=docker/dockerfile:1
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY . .
RUN dart pub get --offline && dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 10001 app \
 && mkdir /data && chown app /data
COPY --from=build /app/server /app/server
USER app
ENV PORT=8080 STORE=sqlite DB_PATH=/data/deferred_links.db
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/app/server"]
