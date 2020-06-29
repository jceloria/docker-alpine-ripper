# build image -------------------------------------------------------------------------------------------------------- #
FROM ubuntu:bionic as builder
COPY makemkv /tmp/makemkv
RUN /tmp/makemkv/build-makemkv.sh

# main image --------------------------------------------------------------------------------------------------------- #
FROM alpine:3.11

COPY --from=builder /tmp/makemkv-install /
COPY . /tmp/build

RUN cd /tmp/build && \
    apk add --no-cache --virtual .build-deps build-base cairo-dev cmake git gobject-introspection-dev \
        jq libcdio-dev libsndfile-dev python3-dev swig zlib-dev && \
    apk --no-cache add curl cdparanoia ddrescue flac libcdio libdiscid openjdk11-jre-headless openrc \
        py3-udev py3-pillow sox util-linux && \
    apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing cdrdao && \
    ./ccextractor/install-ccextractor.sh && ./whipper/install-whipper.sh && udevadm hwdb --update && \
    install -m755 ripper.py /bin && install -m755 ripper.init /etc/init.d/ripper && rc-update add ripper && \
    runDeps=$( \
        scanelf -nBR /usr/lib/python* | \
            awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' | \
            xargs -r apk info --installed | sort -u \
    ) && apk del --no-cache .build-deps && apk add --no-cache ${runDeps} && \
    rm -rf /var/cache/apk/* /tmp/build "${HOME}/.cache"

VOLUME /ripper

ENV PATH "${PATH}:/opt/makemkv/bin"

ENTRYPOINT /sbin/openrc-init

# -------------------------------------------------------------------------------------------------------------------- #
