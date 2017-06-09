#!/bin/sh
set -e

# prefer user supplied CFLAGS, but default to our PHP_CFLAGS
: ${CFLAGS:=$PHP_CFLAGS}
: ${CPPFLAGS:=$PHP_CPPFLAGS}
: ${LDFLAGS:=$PHP_LDFLAGS}
export CFLAGS CPPFLAGS LDFLAGS

srcExists=
if [ -d /usr/src/php ]; then
	srcExists=1
fi
docker-php-source extract
if [ -z "$srcExists" ]; then
	touch /usr/src/php/.docker-delete-me
fi

cd /usr/src/php/ext

usage() {
	echo "usage: $0 [-jN] ext-name [ext-name ...]"
	echo "   ie: $0 gd mysqli"
	echo "       $0 pdo pdo_mysql"
	echo "       $0 -j5 gd mbstring mysqli pdo pdo_mysql shmop"
	echo
	echo 'if custom ./configure arguments are necessary, see docker-php-ext-configure'
	echo
	echo 'Possible values for ext-name:'
	find . \
			-mindepth 2 \
			-maxdepth 2 \
			-type f \
			-name 'config.m4' \
		| xargs -n1 dirname \
		| xargs -n1 basename \
		| sort \
		| xargs
}

opts="$(getopt -o 'h?j:' --long 'help,jobs:' -- "$@" || { usage >&2 && false; })"
eval set -- "$opts"

j=1
while true; do
	flag="$1"
	shift
	case "$flag" in
		--help|-h|'-?') usage && exit 0 ;;
		--jobs|-j) j="$1" && shift ;;
		--) break ;;
		*)
			{
				echo "error: unknown flag: $flag"
				usage
			} >&2
			exit 1
			;;
	esac
done

exts=
for ext; do
	if [ -z "$ext" ]; then
		continue
	fi
	if [ ! -d "$ext" ]; then
		echo >&2 "error: $PWD/$ext does not exist"
		echo >&2
		usage >&2
		exit 1
	fi
	exts="$exts $ext"
done

if [ -z "$exts" ]; then
	usage >&2
	exit 1
fi

pm='unknown'
if [ -e /lib/apk/db/installed ]; then
	pm='apk'
fi

apkDel=
if [ "$pm" = 'apk' ]; then
	if [ -n "$PHPIZE_DEPS" ]; then
		if apk info --installed .phpize-deps-configure > /dev/null; then
			apkDel='.phpize-deps-configure'
		elif ! apk info --installed .phpize-deps > /dev/null; then
			apk add --no-cache --virtual .phpize-deps $PHPIZE_DEPS
			apkDel='.phpize-deps'
		fi
	fi
fi

popDir="$PWD"
for ext in $exts; do
	cd "$ext"
	[ -e Makefile ] || docker-php-ext-configure "$ext"
	make -j"$j"
	make -j"$j" install
	find modules \
		-maxdepth 1 \
		-name '*.so' \
		-exec basename '{}' ';' \
			| xargs -r docker-php-ext-enable
	make -j"$j" clean
	cd "$popDir"
done

if [ "$pm" = 'apk' ] && [ -n "$apkDel" ]; then
	apk del $apkDel
fi

if [ -e /usr/src/php/.docker-delete-me ]; then
	docker-php-source delete
fi
