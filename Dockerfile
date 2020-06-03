# build image -------------------------------------------------------------------------------------------------------- #
FROM ubuntu:bionic as builder
COPY makemkv /tmp/makemkv
RUN /tmp/makemkv/build-makemkv.sh

# main image --------------------------------------------------------------------------------------------------------- #
FROM alpine:3.11

COPY --from=builder /tmp/makemkv-install /
COPY . /tmp/build

RUN cd /tmp/build && \
    apk add --no-cache --virtual .build-deps build-base cmake jq zlib-dev && \
    apk --no-cache add curl ddrescue openrc py3-udev && \
    apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing whipper && \
    patch -p0 < whipper/cdparanoia.patch && ./ccextractor/install-ccextractor.sh && udevadm hwdb --update && \
    install -m755 ripper.py /bin && install -m755 ripper.init /etc/init.d/ripper && rc-update add ripper && \
    runDeps=$( \
        scanelf -nBR /usr/lib/apache2 /usr/sbin/httpd | \
            awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' | \
            xargs -r apk info --installed | sort -u \
    ) && apk del --no-cache .build-deps && apk add --no-cache ${runDeps} && \
    rm -rf /var/cache/apk/* /tmp/build

VOLUME /ripper

ENV PATH="${PATH}:/opt/makemkv/bin"

ENTRYPOINT /sbin/openrc-init

# -------------------------------------------------------------------------------------------------------------------- #
