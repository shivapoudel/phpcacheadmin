<?php
/**
 * The base configuration for phpCacheAdmin
 *
 * @package phpCacheAdmin
 */

return [
	/**
	 * The order of the items also changes the position of the
	 * sidebar links, the first item is also the default dashboard.
	 *
	 * You can comment out (or delete) any dashboard.
	 */
	'dashboards'     => [
		RobiNN\Pca\Dashboards\Server\ServerDashboard::class,
		RobiNN\Pca\Dashboards\Redis\RedisDashboard::class,
		RobiNN\Pca\Dashboards\Memcached\MemcachedDashboard::class,
		RobiNN\Pca\Dashboards\OPCache\OPCacheDashboard::class,
		RobiNN\Pca\Dashboards\APCu\APCuDashboard::class,
		RobiNN\Pca\Dashboards\Realpath\RealpathDashboard::class,
	],
	'redis'          => [
		[
			'name' => 'Localhost',
			'host' => '127.0.0.1',
			'port' => 6379,
		],
	],
	'memcached'      => [
		[
			'name' => 'Localhost',
			'host' => '127.0.0.1',
			'port' => 11211,
		],
	],
	'auth'           => 'pca_basic_auth',
	'auth_username'  => 'admin',
	'auth_password'  => 'password',
	// Decoding / Encoding functions.
	'converters'     => [
		'gzcompress' => [
			'view' => static fn ( string $value ): ?string => @gzuncompress( $value ) !== false ? gzuncompress( $value ) : null,
			'save' => static fn ( string $value ): string => gzcompress( $value ),
		],
		'gzencode'   => [
			'view' => static fn ( string $value ): ?string => @gzdecode( $value ) !== false ? gzdecode( $value ) : null,
			'save' => static fn ( string $value ): string => gzencode( $value ),
		],
		'gzdeflate'  => [
			'view' => static fn ( string $value ): ?string => @gzinflate( $value ) !== false ? gzinflate( $value ) : null,
			'save' => static fn ( string $value ): string => gzdeflate( $value ),
		],
		'zlib'       => [
			'view' => static fn ( string $value ): ?string => @zlib_decode( $value ) !== false ? zlib_decode( $value ) : null,
			'save' => static fn ( string $value ): string => zlib_encode( $value, ZLIB_ENCODING_DEFLATE ),
		],
	],
	// Formatting functions, it runs after decoding.
	'formatters'     => [
		'unserialize' => static function ( string $value ): ?string {
			$unserialize_value = @unserialize( $value, [ 'allowed_classes' => false ] );
			if ( $unserialize_value !== false && is_array( $unserialize_value ) ) {
				try {
					return json_encode( $unserialize_value, JSON_THROW_ON_ERROR );
				} catch ( JsonException ) {
					return null;
				}
			}

			return null;
		},
	],
	// Customizations.
	'timezone'       => 'Asia/Kathmandu',
	'timeformat'     => 'd. m. Y H:i:s',
	'decimalsep'     => ',',
	'thousandssep'   => ' ',
	'listview'       => 'tree',
	'panelrefresh'   => 30,
	'metricsrefresh' => 60,
	'metricstab'     => 1440,
	'hash'           => 'pca',
	'tmpdir'         => __DIR__ . '/tmp',
	'pcapath'        => 'vendor/robinn/phpcacheadmin/',
	'url'            => '/',
];
