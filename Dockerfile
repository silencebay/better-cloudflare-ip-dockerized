# To set multiarch build for Docker hub automated build.
FROM --platform=$TARGETPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG UPSTREAM_LATEST_RELEASE_COMMIT

WORKDIR /go
RUN apk add git curl perl --no-cache

RUN set -eux; \
    \
	sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories; \
	sed -i 's/uk.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories; \
	apk --no-cache --no-progress upgrade; \
	buildDeps=' \
		git \
        jq \
    '; \
    \
    apk add --no-cache --virtual .build-deps \
		$buildDeps \
	;

RUN set -eux; \
    \
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then architecture="linux_amd64." ; fi; \
    if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then architecture="linux_arm64." ; fi; \
    if [ "${TARGETPLATFORM}" = "linux/arm/v7" ] ; then architecture="linux_arm." ; fi; \
    core_download_url=$(curl -L https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest | jq -r --arg architecture "$architecture" '.assets[] | select (.name | contains($architecture)) | .browser_download_url' -); \
    mkdir CloudflareSpeedTest; \
    (cd CloudflareSpeedTest && curl -L $core_download_url | tar -xzvf -)

FROM --platform=$TARGETPLATFORM alpine AS runtime
ARG TARGETPLATFORM
ARG BUILDPLATFORM

COPY --from=builder /go/CloudflareSpeedTest /usr/local/bin/CloudflareSpeedTest
COPY entrypoint.sh /usr/local/bin/
COPY gist.sh /usr/local/bin/
COPY test.sh /usr/local/bin/

RUN set -eux; \
    \
    apk add --no-cache \
        bash \
        curl \
		ca-certificates \
	; \
    chmod +x /usr/local/bin/*; \
    echo "0 */6 * * * /usr/bin/flock -n /tmp/fcj.lockfile /usr/local/bin/test.sh > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontabs/root;

VOLUME [ "/data" ]

WORKDIR /

ENTRYPOINT [ "entrypoint.sh" ]
CMD ["crond", "-f", "-d", "8"]
