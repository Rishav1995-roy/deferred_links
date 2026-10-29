# syntax=docker/dockerfile:1
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY . .
# sqlite3 3.x ships its SQLite through a build hook, which `dart compile exe` does not run;
# `dart build cli` produces bundle/bin/server + bundle/lib/libsqlite3.so.
RUN dart pub get --offline && dart build cli -t bin/server.dart -o /app/out

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 10001 app \
 && mkdir /data && chown app /data
COPY --from=build /app/out/bundle/ /app/
USER app
ENV PORT=8080 STORE=sqlite DB_PATH=/data/deferred_links.db
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/app/bin/server"]
