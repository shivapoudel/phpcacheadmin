FROM php:8.3-fpm AS build

# Install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libavif-dev \
		libfreetype6-dev \
		libicu-dev \
		libjpeg-dev \
		libmagickwand-dev \
		libpng-dev \
		libwebp-dev \
		libzip-dev \
		libonig-dev \
		liblz4-dev \
		libzstd-dev \
		libsasl2-dev \
		libmemcached-dev \
		zlib1g-dev \
		libssl-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-avif \
		--with-freetype \
		--with-jpeg \
		--with-webp \
	; \
	docker-php-ext-install -j "$(nproc)" \
		bcmath \
		exif \
		gd \
		intl \
		mysqli \
		zip \
        mbstring \
	; \
# pecl will claim success even if one install fails, so we need to perform each install separately
	pecl install imagick-3.8.0; \
	pecl install zstd-0.15.2; \
	pecl install igbinary-3.2.16; \
	pecl install msgpack-3.0.0; \
	pecl install --configureoptions 'enable-memcached-igbinary="yes" enable-memcached-json="yes" enable-memcached-msgpack="yes" with-libmemcached-dir="/usr"' memcached-3.4.0; \
	pecl install --configureoptions 'enable-redis="yes" disable-redis-session="yes" disable-redis-json="yes" enable-redis-igbinary="yes" enable-redis-msgpack="yes" enable-redis-zstd="yes" with-libzstd="yes" enable-redis-lzf="yes" with-liblzf="yes" enable-redis-lz4="yes" with-liblz4="yes"' redis-6.3.0; \
	\
	docker-php-ext-enable \
		imagick \
		zstd \
		igbinary \
		msgpack \
		memcached \
		redis \
	; \
	rm -r /tmp/pear; \
	\
# some misbehaving extensions end up outputting to stdout 🙈 (https://github.com/docker-library/wordpress/issues/669#issuecomment-993945967)
	out="$(php -r 'exit(0);')"; \
	[ -z "$out" ]; \
	err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]; \
	\
	extDir="$(php -r 'echo ini_get("extension_dir");')"; \
	[ -d "$extDir" ]; \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$extDir"/*.so \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u > /tmp/runtime-packages.txt; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	! { ldd "$extDir"/*.so | grep 'not found'; }; \
# check for output like "PHP Warning:  PHP Startup: Unable to load dynamic library 'foo' (tried: ...)
	err="$(php --version 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
	docker-php-ext-enable opcache; \
	{ \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

FROM php:8.3-fpm AS runtime

# Install persistent runtime dependencies
COPY --from=build /tmp/runtime-packages.txt /tmp/runtime-packages.txt
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        nano \
        ghostscript \
        $(cat /tmp/runtime-packages.txt || true) \
    ; \
    rm -rf /tmp/runtime-packages.txt /var/lib/apt/lists/*

# Copy PHP extensions and configuration from build stage
COPY --from=build /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=build /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

VOLUME /var/www/html

# Create phpinfo page
RUN echo "<?php phpinfo();" > index.php

# Use PHP built-in server for testing
CMD ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/html"]
