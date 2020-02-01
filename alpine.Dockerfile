ARG ALPINE_VERSION=3.11
ARG GO_VERSION=1.13.7

# See https://github.com/golang/go/issues/14481
FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS race
WORKDIR /tmp/race
RUN apk --update -q --progress --no-cache add git g++
RUN git clone --single-branch https://github.com/llvm-mirror/compiler-rt . && \
    git reset --hard 69445f095c22aac2388f939bedebf224a6efcdaf
RUN wget -q https://github.com/golang/go/files/4114545/0001-upstream-master-69445f095-hack-to-make-Go-s-race-flag-work-on-Alpine.patch.gz -O patch.gz && \
   gunzip patch.gz && \
   patch -p1 -i patch
WORKDIR /tmp/race/lib/tsan/go
RUN sed -e 's,-Wno-unknown-warning-option,-Wno-error=deprecated,' -i buildgo.sh
RUN ./buildgo.sh

FROM qmcgaw/basedevcontainer:alpine
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=local
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
LABEL \
    org.opencontainers.image.authors="quentin.mcgaw@gmail.com" \
    org.opencontainers.image.created=$BUILD_DATE \
    org.opencontainers.image.version=$VERSION \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.url="https://github.com/qdm12/godevcontainer" \
    org.opencontainers.image.documentation="https://github.com/qdm12/godevcontainer" \
    org.opencontainers.image.source="https://github.com/qdm12/godevcontainer" \
    org.opencontainers.image.title="Go Dev container Alpine" \
    org.opencontainers.image.description="Go development container for Visual Studio Code Remote Containers development"
USER root
# TODO use build args
COPY --from=golang:1.13.7-alpine3.11 /usr/local/go /usr/local/go
COPY --from=race /tmp/race/lib/tsan/go/race_linux_amd64.syso /usr/local/go/src/runtime/race/race_linux_amd64.syso
ENV GOPATH=/go
ENV PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
WORKDIR $GOPATH
RUN chown ${USERNAME}:${USER_GID} $GOPATH && \
    chmod 777 $GOPATH
# Install Alpine packages
RUN apk add -q --update --progress --no-cache g++ && \
    rm -rf /var/cache/apk/*
# Shell setup
COPY --chown=${USER_UID}:${USER_GID} shell/.zshrc-specific shell/.welcome.sh /home/${USERNAME}/
COPY shell/.zshrc-specific shell/.welcome.sh /root/
# Install Go packages
RUN wget -O- -nv https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /bin -d v1.22.2
ENV GO111MODULE=on
RUN go get -v golang.org/x/tools/gopls@v0.3.0 && \
    chown ${USERNAME}:${USER_GID} /go/bin/* && \
    chmod 500 /go/bin/* && \
    rm -rf /go/pkg /go/src/* /root/.cache/go-build
RUN go get -v \
    # Base Go tools needed for VS code Go extension
    github.com/ramya-rao-a/go-outline \
    github.com/acroca/go-symbols \
    github.com/uudashr/gopkgs/cmd/gopkgs@latest \
    golang.org/x/tools/cmd/guru \
    golang.org/x/tools/cmd/gorename \
    golang.org/x/lint/golint \
    github.com/go-delve/delve/cmd/dlv \
    # Extra tools integrating with VS code
    github.com/fatih/gomodifytags \
    github.com/haya14busa/goplay/cmd/goplay \
    github.com/josharian/impl \
    github.com/tylerb/gotype-live \
    github.com/cweill/gotests/... \
    github.com/davidrjenni/reftools/cmd/fillstruct \
    # Terminal tools
    github.com/vektra/mockery/... \
    2>&1 && \
    chown ${USERNAME}:${USER_GID} /go/bin/* && \
    chmod 500 /go/bin/* && \
    rm -rf /go/pkg /go/src/* /root/.cache/go-build
USER ${USERNAME}
