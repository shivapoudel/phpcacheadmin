FROM php:8.3-fpm AS build

ARG UID=33
ARG GID=33
ENV DEBIAN_FRONTEND=noninteractive

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
		| sort -u > /tmp/runtime-packages.txt \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	! { ldd "$extDir"/*.so | grep 'not found'; }; \
# check for output like "PHP Warning:  PHP Startup: Unable to load dynamic library 'foo' (tried: ...)
	err="$(php --version 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]

# Install composer
RUN curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
RUN export COMPOSER_HASH=`curl -sS https://composer.github.io/installer.sig` && php -r "if (hash_file('SHA384', '/tmp/composer-setup.php') === '$COMPOSER_HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('/tmp/composer-setup.php'); } echo PHP_EOL;"
RUN php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
RUN rm /tmp/composer-setup.php

# Set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
	docker-php-ext-enable opcache; \
	{ \
		echo 'opcache.enable=1'; \
		echo 'opcache.enable_cli=1'; \
		echo 'opcache.memory_consumption=256'; \
		echo 'opcache.interned_strings_buffer=32'; \
		echo 'opcache.max_accelerated_files=20000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.enable_file_override=1'; \
		echo 'opcache.log_verbosity_level=1'; \
		echo 'opcache.error_log=/tmp/php_opcache.log'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
RUN { \
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
RUN { \
		echo 'expose_php=Off'; \
        echo 'file_uploads=On'; \
        echo 'allow_url_fopen=Off'; \
        echo 'allow_url_include=Off'; \
        echo 'session.cookie_httponly=On'; \
        echo 'session.cookie_secure=On'; \
        echo 'session.use_strict_mode=On'; \
	} > /usr/local/etc/php/conf.d/security-recommended.ini
RUN { \
		echo 'max_execution_time=3000'; \
		echo 'max_input_time=3000'; \
		echo 'max_input_vars=100000'; \
		echo 'memory_limit=1024M'; \
		echo 'post_max_size=2048M'; \
		echo 'upload_max_filesize=2048M'; \
		echo 'output_buffering=4096'; \
		echo 'default_socket_timeout=300'; \
	} > /usr/local/etc/php/conf.d/wordpress-recommended.ini
RUN { \
		echo 'memcached.serializer=igbinary'; \
		echo 'memcached.use_sasl=0'; \
	} > /usr/local/etc/php/conf.d/memcached-recommended.ini

FROM php:8.3-fpm AS runtime

ARG UID=33
ARG GID=33
ENV DEBIAN_FRONTEND=noninteractive
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV EDITOR=nano
ENV CHOWN_ON_START=false
ENV CHOWN_PATHS="/var/www/html/wp-content/plugins /var/www/html/wp-content/themes"

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

# Set working directory
WORKDIR /var/www/html

# Create phpinfo page
RUN echo "<?php phpinfo();" > index.php

# Use PHP built-in server for testing
CMD ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/html"]
