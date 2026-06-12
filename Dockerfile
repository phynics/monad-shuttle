FROM swift:6.0-jammy AS build

WORKDIR /workspace

COPY Shuttle/Package.swift Shuttle/Package.resolved ./Shuttle/
COPY Shuttle/Sources ./Shuttle/Sources
COPY Shuttle/Tests ./Shuttle/Tests
COPY PositronicKit ./PositronicKit

WORKDIR /workspace/Shuttle

RUN swift build -c release --product ShuttleServer

FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /workspace/Shuttle/.build/release/ShuttleServer /usr/local/bin/ShuttleServer

ENV SHUTTLE_CONFIG_PATH=/config/shuttle.yaml

ENTRYPOINT ["/usr/local/bin/ShuttleServer"]
CMD ["--config", "/config/shuttle.yaml", "--host", "0.0.0.0", "--port", "8080"]
