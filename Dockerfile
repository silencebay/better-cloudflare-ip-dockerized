# To set multiarch build for Docker hub automated build.
FROM --platform=$TARGETPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG UPSTREAM_LATEST_RELEASE_COMMIT
ARG CHANGESOURCE=false

WORKDIR /go
RUN apk add git curl perl --no-cache

RUN <<EOF
    set -eux

    if [ ${CHANGESOURCE} = true ]; then
	    sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
	    sed -i 's/uk.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
    fi

	apk --no-cache --no-progress upgrade
	buildDeps='
		git
        jq
    '
    apk add --no-cache --virtual .build-deps \
		$buildDeps	

    case "${TARGETPLATFORM}" in
        "linux/amd64")    architecture="linux_amd64" ;;
        "linux/arm64")    architecture="linux_arm64" ;;
        "linux/arm/v7")   architecture="linux_armv7" ;;
        *)                echo "Unsupported platform: ${TARGETPLATFORM}"; exit 1 ;;
    esac

    repo_api="https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases"
    asset_pattern="^CloudflareST_.*${architecture}\."
    core_download_url=$(curl -L "${repo_api}?per_page=100" \
        | jq -r --arg asset "${asset_pattern}" '
        [.[] | select((.assets | length) > 0)]
        | first
        | .assets[]
        | select (.name | test($asset))
        | .browser_download_url' -)

    mkdir CloudflareSpeedTest
    (cd CloudflareSpeedTest && curl -L "${core_download_url}" | tar -xzvf -)
EOF

FROM --platform=$TARGETPLATFORM alpine AS runtime
ARG TARGETPLATFORM
ARG BUILDPLATFORM

COPY --from=builder /go/CloudflareSpeedTest /usr/local/bin/CloudflareSpeedTest
COPY root/. /

RUN <<EOF
    set -eux

    apk add --no-cache \
        bash \
        curl \
        jq \
        ca-certificates

    # Create custom tasks directory
    mkdir -p /app/tasks/custom
    
    # Set permissions for all script directories and files
    chmod +x /usr/local/bin/* /app/tasks/*.sh /app/lib/*.sh /app/tasks/custom/*.sh
EOF

VOLUME [ "/data" ]

WORKDIR /

ENTRYPOINT [ "entrypoint.sh" ]
CMD ["crond", "-f", "-d", "8"]
