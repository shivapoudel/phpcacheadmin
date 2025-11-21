<?php
/**
 * Bootstrap file for phpCacheAdmin.
 *
 * @package phpCacheAdmin
 */

use Env\Env;

use function Env\env;

/** Autoload composer packages. */
$autoloader = __DIR__ . '/vendor/autoload.php';
if ( is_readable( $autoloader ) ) {
	require_once $autoloader;
} else {
	die( 'Composer autoload file not found. Please run composer install in the root directory.' );
}

/** Use $_ENV instead of getenv() */
Env::$options |= Env::USE_ENV_ARRAY;

/**
 * Use Dotenv to set required environment variables and load .env file in root
 * .env.local will override .env if it exists
 */
if ( file_exists( __DIR__ . '/.env' ) ) {
	$env_files = file_exists( __DIR__ . '/.env.local' )
		? [ '.env', '.env.local' ]
		: [ '.env' ];

	$repository = Dotenv\Repository\RepositoryBuilder::createWithNoAdapters()
		->addAdapter( Dotenv\Repository\Adapter\EnvConstAdapter::class )
		->addWriter( Dotenv\Repository\Adapter\PutenvAdapter::class )
		->immutable()
		->make();

	$dotenv = Dotenv\Dotenv::create( $repository, __DIR__, $env_files, false );
	$dotenv->load();
} else {
	// Load phpCacheAdmin configuration.
	RobiNN\Pca\Config::setConfigPath( __DIR__ . '/config.php' );
}

// Prevent caching for the different browsers.
header( 'Expires: Wed, 11 Jan 1984 05:00:00 GMT' );
header( 'Cache-Control: no-cache, must-revalidate, max-age=0, no-store, private' );

/**
 * Basic authentication function.
 *
 * @since 1.0.0
 */
function pca_basic_auth(): void {
	$username = env( 'PCA_AUTH_USERNAME' ) ?: 'admin';
	$password = env( 'PCA_AUTH_PASSWORD' ) ?: 'password';

	// Handle logout.
	if ( isset( $_GET['logout'] ) ) { // @codingStandardsIgnoreLine
		setcookie( 'auth_reset', '1', time() + 60, '/' );

		// @codingStandardsIgnoreStart
		$clean_uri = strtok( $_SERVER['REQUEST_URI'], '?' ); // @codingStandardsIgnoreLine
		$is_https  = (
			( isset( $_SERVER['HTTPS'] ) && ( 'on' === strtolower( $_SERVER['HTTPS'] ) || '1' === (string) $_SERVER['HTTPS'] ) ) ||
			( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && 'https' === $_SERVER['HTTP_X_FORWARDED_PROTO'] )
		);
		// @codingStandardsIgnoreEnd

		header( 'Location: http' . ( $is_https ? 's' : '' ) . '://' . $_SERVER['HTTP_HOST'] . $clean_uri ); // @codingStandardsIgnoreLine
		exit;
	}

	// If logout cookie is present.
	if ( isset( $_COOKIE['auth_reset'] ) ) {
		setcookie( 'auth_reset', '', time() - 3600, '/' );

		header( 'WWW-Authenticate: Basic realm="phpCacheAdmin Login"' );
		header( 'HTTP/1.0 401 Unauthorized' );
		exit( 'You have been logged out.' );
	}

	// Check authentication credentials.
	if (
		! isset( $_SERVER['PHP_AUTH_USER'], $_SERVER['PHP_AUTH_PW'] ) ||
		$username !== $_SERVER['PHP_AUTH_USER'] || $password !== $_SERVER['PHP_AUTH_PW']
	) {
		header( 'WWW-Authenticate: Basic realm="phpCacheAdmin Login"' );
		header( 'HTTP/1.0 401 Unauthorized' );
		exit( 'Incorrect username or password!' );
	}
}

$auth = false;

// Execute authentication callback if available.
$auth_callback = RobiNN\Pca\Config::get( 'auth' );
if ( is_callable( $auth_callback ) ) {
	$auth = true;
	$auth_callback();
}

// Render phpCacheAdmin.
echo ( new RobiNN\Pca\Admin() )->render( $auth ); // @codingStandardsIgnoreLine
