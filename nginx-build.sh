#!/usr/bin/env bash
# -------------------------------------------------------------------------
#  Nginx-ee - Automated Nginx compilation from source
# -------------------------------------------------------------------------
# Website:       https://virtubox.net
# GitHub:        https://github.com/VirtuBox/nginx-ee
# Copyright (c) 2019 VirtuBox <contact@virtubox.net>
# This script is licensed under M.I.T
# -------------------------------------------------------------------------
# Version 3.6.2 - 2019-05-01
# -------------------------------------------------------------------------

##################################
# Check requirements
##################################

# Check if user is root
[ "$(id -u)" != "0" ] && {
    echo "Error: You must be root or use sudo to run this script"
    exit 1
}

##################################
# Use config.inc if available
##################################

if [ -f ./config.inc ]; then

    . ./config.inc

else

    ##################################
    # Parse script arguments
    ##################################

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --pagespeed)
            PAGESPEED="y"
            PAGESPEED_RELEASE="2"
            ;;
        --pagespeed-beta)
            PAGESPEED="y"
            PAGESPEED_RELEASE="1"
            ;;
        --full)
            PAGESPEED="y"
            PAGESPEED_RELEASE="2"
            NAXSI="y"
            RTMP="y"
            ;;
        --naxsi)
            NAXSI="y"
            ;;
        --openssl-dev)
            OPENSSL_LIB="2"
            ;;
        --openssl-system)
            OPENSSL_LIB="3"
            ;;
        --libressl)
            LIBRESSL="y"
            ;;
        --rtmp)
            RTMP="y"
            ;;
        --latest | --mainline)
            NGINX_RELEASE="1"
            ;;
        --stable)
            NGINX_RELEASE="2"
            ;;
        -i | --interactive)
            INTERACTIVE_SETUP="1"
            ;;
        --dynamic)
            DYNAMIC_MODULES="y"
            ;;
        --cron | --cronjob)
            CRON_SETUP="y"
            ;;
        --travis)
            TRAVIS_BUILD="1"
            ;;
        *) ;;
        esac
        shift
    done

fi

# updating packages list
[ -z "$TRAVIS_BUILD" ] && {
    apt-get update -qq
}
# checking if curl is installed
[ -z "$(command -v curl)" ] && {
    apt-get -y install curl
} >> /tmp/nginx-ee.log 2>&1

# Checking if lsb_release is installed
[ -z "$(command -v lsb_release)" ] && {
    apt-get -y install lsb-release
} >> /tmp/nginx-ee.log 2>&1

# checking if tar is installed
[ -z "$(command -v tar)" ] && {
    apt-get -y install tar
} >> /tmp/nginx-ee.log 2>&1

##################################
# Variables
##################################

DIR_SRC="/usr/local/src"
NGINX_EE_VER="3.6.2"
NGINX_MAINLINE="$(curl -sL https://nginx.org/en/download.html 2>&1 | grep -E -o 'nginx\-[0-9.]+\.tar[.a-z]*' | awk -F "nginx-" '/.tar.gz$/ {print $2}' | sed -e 's|.tar.gz||g' | head -n 1 2>&1)"
NGINX_STABLE="$(curl -sL https://nginx.org/en/download.html 2>&1 | grep -E -o 'nginx\-[0-9.]+\.tar[.a-z]*' | awk -F "nginx-" '/.tar.gz$/ {print $2}' | sed -e 's|.tar.gz||g' | head -n 2 | grep 1.16 2>&1)"
LIBRESSL_VER="2.9.1"
OPENSSL_VER="1.1.1b"
TLS13_CIPHERS="TLS13+AESGCM+AES256:TLS13+AESGCM+AES128:TLS13+CHACHA20:EECDH+CHACHA20:EECDH+AESGCM:EECDH+AES"
OS_ARCH="$(uname -m)"
OS_DISTRO_FULL="$(lsb_release -ds)"
DISTRO_ID="$(lsb_release -si)"
DISTRO_CODENAME=$(lsb_release -sc)
DEB_CFLAGS="$(dpkg-buildflags --get CPPFLAGS) -Wno-error=date-time"
DEB_LFLAGS="$(dpkg-buildflags --get LDFLAGS)"
OPENSSL_COMMIT="ee215c7eea91f193d4765127eb31332758753058"
PCRE_VER=$(curl -sL https://ftp.pcre.org/pub/pcre/ | grep -E -o 'pcre\-[0-9.]+\.tar[.a-z]*gz' | awk -F "pcre-" '/.tar.gz$/ {print $2}' | sed -e 's|.tar.gz||g' | tail -n 1 2>&1)

# Colors
CSI='\033['
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CEND="${CSI}0m"

##################################
# Initial check & cleanup
##################################

# clean previous install log

echo "" > /tmp/nginx-ee.log

# detect Plesk
[ -d /etc/psa ] && {
    PLESK_VALID="YES"
}

# detect easyengine
[ -f /var/lib/ee/ee.db ] && {
    EE_VALID="YES"
}

[ -f /var/lib/wo/dbase.db ] && {
    WO_VALID="YES"
}

[ -z "$(command -v nginx)" ] && {
    NGINX_FROM_SCRATCH="1"
}

##################################
# Installation menu
##################################

echo ""
echo "Welcome to the nginx-ee bash script v${NGINX_EE_VER}"
echo ""

# interactive
if [ "$INTERACTIVE_SETUP" = "1" ]; then
    clear
    echo ""
    echo "Do you want to compile the latest Nginx [1] Mainline v${NGINX_MAINLINE} or [2] Stable v${NGINX_STABLE} Release ?"
    while [[ "$NGINX_RELEASE" != "1" && "$NGINX_RELEASE" != "2" ]]; do
        echo -e "Select an option [1-2]: " && read -r NGINX_RELEASE
    done
    echo -e '\nDo you want Ngx_Pagespeed ? (y/n)'
    while [[ "$PAGESPEED" != "y" && "$PAGESPEED" != "n" ]]; do
        echo -e "Select an option [y/n]: " && read -r PAGESPEED
    done
    if [ "$PAGESPEED" = "y" ]; then
        echo -e '\nWhat Ngx_Pagespeed release do you want ?\n'
        echo -e '  [1] Beta Release'
        echo -e '  [2] Stable Release\n'
        while [[ "$PAGESPEED_RELEASE" != "1" && "$PAGESPEED_RELEASE" != "2" ]]; do
            echo -e "Select an option [1-2]: " && read -r PAGESPEED_RELEASE
        done
    fi
    echo -e '\nDo you prefer to compile Nginx with OpenSSL [1] or LibreSSL [2] ? (y/n)'
    echo -e '  [1] OpenSSL'
    echo -e '  [2] LibreSSL\n'
    while [[ "$SSL_LIB_CHOICE" != "1" && "$SSL_LIB_CHOICE" != "2" ]]; do
        echo -e "Select an option [1-2]: " && read -r SSL_LIB_CHOICE
    done
    if [ "$SSL_LIB_CHOICE" = "1" ]; then
        echo -e '\nWhat OpenSSL release do you want ?\n'
        echo -e '  [1] OpenSSL stable 1.1.1b'
        echo -e '  [2] OpenSSL dev 3.0.0-dev\n'
        echo -e '  [3] OpenSSL from system lib\n'
        while [[ "$OPENSSL_LIB" != "1" && "$OPENSSL_LIB" != "2" && "$OPENSSL_LIB" != "3" ]]; do
            echo -e "Select an option [1-2-3]: " && read -r OPENSSL_LIB
        done
    else
        LIBRESSL="y"
    fi
    echo -e '\nDo you want NAXSI WAF (still experimental)? (y/n)'
    while [[ "$NAXSI" != "y" && "$NAXSI" != "n" ]]; do
        echo -e "Select an option [y/n]: " && read -r NAXSI
    done
    echo -e '\nDo you want RTMP streaming module (used for video streaming) ? (y/n)'
    while [[ "$RTMP" != "y" && "$RTMP" != "n" ]]; do
        echo -e "Select an option [y/n]: " && read -r RTMP
    done
    echo -e '\nDo you want to build modules as dynamic modules? (y/n)'
    while [[ "$DYNAMIC_MODULES" != "y" && "$DYNAMIC_MODULES" != "n" ]]; do
        echo -e "Select an option [y/n]: " && read -r DYNAMIC_MODULES
    done
    echo -e '\nDo you want to setup nginx-ee auto-update cronjob ? (y/n)'
    while [[ "$CRON_SETUP" != "y" && "$CRON_SETUP" != "n" ]]; do
        echo -e "Select an option [y/n]: " && read -r CRON_SETUP
    done
    echo ""
fi

##################################
# Set nginx release and HPACK
##################################

if [ "$NGINX_RELEASE" = "2" ]; then
    NGINX_VER="$NGINX_STABLE"
    NGX_HPACK="--with-http_v2_hpack_enc"
else
    NGINX_VER="$NGINX_MAINLINE"
    NGX_HPACK="--with-http_v2_hpack_enc"
fi

##################################
# Set RTMP module
##################################

if [ "$RTMP" = "y" ]; then
    NGX_RTMP="--add-module=../nginx-rtmp-module "
    RTMP_VALID="YES"
else
    NGX_RTMP=""
    RTMP_VALID="NO"
fi

##################################
# Set Naxsi module
##################################

if [ "$NAXSI" = "y" ]; then
    NGX_NAXSI="--add-module=../naxsi/naxsi_src "
    NAXSI_VALID="YES"
else
    NGX_NAXSI=""
    NAXSI_VALID="NO"
fi

##################################
# Set OPENSSL/LIBRESSL lib
##################################

if [ "$LIBRESSL" = "y" ]; then
    NGX_SSL_LIB="--with-openssl=../libressl"
    LIBRESSL_VALID="YES"
    OPENSSL_OPT=""
else
    if [ "$OS_ARCH" = 'x86_64' ]; then
        if [ "$DISTRO_ID" = "Ubuntu" ]; then
            OPENSSL_OPT="enable-ec_nistp_64_gcc_128 enable-tls1_3 no-ssl3-method -march=native -ljemalloc"
        else
            OPENSSL_OPT="enable-tls1_3"
        fi
    fi
    if [ "$OPENSSL_LIB" = "2" ]; then
        NGX_SSL_LIB="--with-openssl=../openssl"
        OPENSSL_VALID="3.0.0-dev"
        LIBSSL_DEV=""
    elif [ "$OPENSSL_LIB" = "3" ]; then
        NGX_SSL_LIB=""
        OPENSSL_VALID="from system"
        LIBSSL_DEV="libssl-dev"
    else
        NGX_SSL_LIB="--with-openssl=../openssl"
        OPENSSL_VALID="1.1.1b Stable"
        LIBSSL_DEV=""
    fi
fi

##################################
# Set Pagespeed module
##################################

if [ -n "$PAGESPEED_RELEASE" ]; then
    if [ "$PAGESPEED_RELEASE" = "1" ]; then
        NGX_PAGESPEED="--add-module=../incubator-pagespeed-ngx-latest-beta "
        PAGESPEED_VALID="beta"
    elif [ "$PAGESPEED_RELEASE" = "2" ]; then
        NGX_PAGESPEED="--add-module=../incubator-pagespeed-ngx-latest-stable "
        PAGESPEED_VALID="stable"
    fi
else
    NGX_PAGESPEED=""
    PAGESPEED_VALID="NO"
fi

##################################
# Set Plesk configuration
##################################

if [ "$PLESK_VALID" = "YES" ]; then
    NGX_USER="--user=nginx --group=nginx"
else
    NGX_USER=""
fi

if [ "$DYNAMIC_MODULES" = "y" ]; then
    DYNAMIC_MODULES_VALID="YES"
else
    DYNAMIC_MODULES_VALID="NO"
fi

##################################
# Set Libjemalloc
##################################

if [ "$DISTRO_CODENAME" = "disco" ]; then
    LIBJEMALLOC="libjemalloc2"
else
    LIBJEMALLOC="libjemalloc1"
fi

##################################
# Display Compilation Summary
##################################

echo ""
echo -e "${CGREEN}##################################${CEND}"
echo " Compilation summary "
echo -e "${CGREEN}##################################${CEND}"
echo ""
echo " Detected OS : $OS_DISTRO_FULL"
echo " Detected Arch : $OS_ARCH"
echo ""
echo -e "  - Nginx release : $NGINX_VER"
[ -n "$OPENSSL_VALID" ] && {
    echo -e "  - OPENSSL : $OPENSSL_VALID"
}
[ -n "$LIBRESSL_VALID" ] && {
    echo -e "  - LIBRESSL : $LIBRESSL_VALID"
}
echo "  - Dynamic modules $DYNAMIC_MODULES_VALID"
echo "  - Pagespeed : $PAGESPEED_VALID"
echo "  - Naxsi : $NAXSI_VALID"
echo "  - RTMP : $RTMP_VALID"
[ -n "$EE_VALID" ] && {
    echo "  - EasyEngine : $EE_VALID"
}
[ -n "$WO_VALID" ] && {
    echo "  - WordOps : $WO_VALID"
}
[ -n "$PLESK_VALID" ] && {
    echo "  - Plesk : $PLESK_VALID"
}
echo ""

##################################
# Install dependencies
##################################

_install_dependencies() {
    echo -ne '       Installing dependencies               [..]\r'
    if {
        DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confold" -y install \
            git build-essential libtool automake autoconf \
            libgd3 libgd-dev libgeoip-dev "$LIBJEMALLOC" libjemalloc-dev \
            libbz2-1.0 libreadline-dev libbz2-dev libbz2-ocaml libbz2-ocaml-dev software-properties-common tar \
            libgoogle-perftools-dev perl libperl-dev libpam0g-dev libbsd-dev gnupg gnupg2 \
            libgmp-dev autotools-dev checkinstall ccache libxml2 libxml2-dev "$LIBSSL_DEV"
    } >> /tmp/nginx-ee.log 2>&1; then
        echo -ne "       Installing dependencies                [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "        Installing dependencies              [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1

    fi
}

##################################
# Setup Nginx from scratch
##################################

_nginx_from_scratch_setup() {

    echo -ne '       Setting Up Nginx configurations        [..]\r'
    if {
        # clone custom nginx configuration
        [ ! -d /etc/nginx ] && {
            git clone https://github.com/VirtuBox/nginx-config.git /etc/nginx
        } >> /tmp/nginx-ee.log 2>&1

        # create nginx temp directory
        mkdir -p /var/lib/nginx/{body,fastcgi,proxy,scgi,uwsgi}
        # create nginx cache directory
        [ ! -d /var/cache/nginx ] && {
            mkdir -p /var/cache/nginx
        }
        [ ! -d /var/run/nginx-cache ] && {
            mkdir -p /var/run/nginx-cache
        }
        [ ! -d /var/log/nginx ] && {
            mkdir -p /var/log/nginx
            chmod 640 /var/log/nginx
            chown -R www-data:adm /var/log/nginx
        }

        # set proper permissions
        chown -R www-data:root /var/lib/nginx /var/cache/nginx /var/run/nginx-cache

        # create websites directory
        [ ! -d /var/www/html ] && {
            mkdir -p /var/www/html
        }

        {
            # download default nginx page
            wget -O /var/www/html/index.nginx-debian.html https://raw.githubusercontent.com/VirtuBox/nginx-ee/master/var/www/html/index.nginx-debian.html
            mkdir -p /etc/nginx/sites-enabled
            ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
            # download nginx systemd service
            [ ! -f /lib/systemd/system/nginx.service ] && {
                wget -O /lib/systemd/system/nginx.service https://raw.githubusercontent.com/VirtuBox/nginx-ee/master/etc/systemd/system/nginx.service
                systemctl enable nginx.service
            }

            # download logrotate configuration
            wget -O /etc/logrotate.d/nginx https://raw.githubusercontent.com/VirtuBox/nginx-ee/master/etc/logrotate.d/nginx

        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Setting Up Nginx configurations        [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Setting Up Nginx configurations        [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Install gcc7 or gcc8 from PPA
##################################
# gcc7 if Nginx is compiled with RTMP module
# otherwise gcc8 is used

_gcc_ubuntu_setup() {

    if [ ! -f /etc/apt/sources.list.d/jonathonf-ubuntu-gcc-"$(lsb_release -sc)".list ]; then
        {
            echo "### adding gcc repository ###"
            add-apt-repository -y ppa:jonathonf/gcc
            apt-get update
        } >> /dev/null 2>&1
    fi
    if [ "$RTMP" != "y" ]; then
        echo -ne '       Installing gcc-8                       [..]\r'
        if {
            echo "### installing gcc8 ###"
            apt-get install gcc-8 g++-8 -y
        } >> /dev/null 2>&1; then
            echo -ne "       Installing gcc-8                       [${CGREEN}OK${CEND}]\\r"
            echo -ne '\n'
        else
            echo -e "        Installing gcc-8                      [${CRED}FAIL${CEND}]"
            echo -e '\n      Please look at /tmp/nginx-ee.log\n'
            exit 1
        fi
        {
            # update gcc alternative to use gcc-8 by default
            update-alternatives --remove-all gcc
            update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 80 --slave /usr/bin/g++ g++ /usr/bin/g++-8
        } >> /dev/null 2>&1
    else
        echo -ne '       Installing gcc-7                       [..]\r'

        if {
            echo "### installing gcc7 ###"
            apt-get install gcc-7 g++-7 -y
        } >> /dev/null 2>&1; then
            echo -ne "       Installing gcc-7                       [${CGREEN}OK${CEND}]\\r"
            echo -ne '\n'
        else
            echo -e "        Installing gcc-7                      [${CRED}FAIL${CEND}]"
            echo -e '\n      Please look at /tmp/nginx-ee.log\n'
            exit 1
        fi
        {
            # update gcc alternative to use gcc-7 by default
            update-alternatives --remove-all gcc
            update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 80 --slave /usr/bin/g++ g++ /usr/bin/g++-7
        } >> /dev/null 2>&1
    fi

}

##################################
# Install ffmpeg for rtmp module
##################################

_rtmp_setup() {
    echo -ne '       Installing FFMPEG for RTMP module      [..]\r'
    if {

        if [ "$DISTRO_ID" = "Ubuntu" ]; then
            if [ ! -f /etc/apt/sources.list.d/jonathonf-ubuntu-ffmpeg-4-"$(lsb_release -sc)".list ]; then
                add-apt-repository -y ppa:jonathonf/ffmpeg-4
                apt-get update
                apt-get install ffmpeg -y
            fi
        else
            apt-get install ffmpeg -y
        fi
    } >> /dev/null 2>&1; then
        echo -ne "       Installing FFMPEG for RMTP module      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Installing FFMPEG for RMTP module      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
}

##################################
# Cleanup modules
##################################

_cleanup_modules() {

    cd "$DIR_SRC" || exit 1
    rm -rf /usr/local/src/{*.tar.gz,nginx,nginx-1.*,pcre,zlib,incubator-pagespeed-*,build_ngx_pagespeed.sh,install,ngx_http_redis,naxsi}

}

##################################
# Download additional modules
##################################

_download_modules() {

    echo -ne '       Downloading additionals modules        [..]\r'

    if {
        echo "### downloading additionals modules ###"
        # cache_purge module
        { [ -d "$DIR_SRC/ngx_cache_purge" ] && {
            git -C "$DIR_SRC/ngx_cache_purge" pull origin master
        }; } || {
            git clone https://github.com/FRiCKLE/ngx_cache_purge.git
        }
        # memcached module
        { [ -d "$DIR_SRC/memc-nginx-module" ] && {
            git -C "$DIR_SRC/memc-nginx-module" pull origin master
        }; } || {
            git clone https://github.com/openresty/memc-nginx-module.git
        }
        # devel kit
        { [ -d "$DIR_SRC/ngx_devel_kit" ] && {
            git -C "$DIR_SRC/ngx_devel_kit" pull origin master
        }; } || {
            git clone https://github.com/simpl/ngx_devel_kit.git
        }
        # headers-more module
        { [ -d "$DIR_SRC/headers-more-nginx-module" ] && {
            git -C "$DIR_SRC/headers-more-nginx-module" pull origin master
        }; } || {
            git clone https://github.com/openresty/headers-more-nginx-module.git
        }
        # echo module
        { [ -d "$DIR_SRC/echo-nginx-module" ] && {
            git -C "$DIR_SRC/echo-nginx-module" pull origin master
        }; } || {
            git clone https://github.com/openresty/echo-nginx-module.git
        }
        # http_substitutions_filter module
        { [ -d "$DIR_SRC/ngx_http_substitutions_filter_module" ] && {
            git -C "$DIR_SRC/ngx_http_substitutions_filter_module" pull origin master
        }; } || {
            git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git
        }
        # redis2 module
        { [ -d "$DIR_SRC/redis2-nginx-module" ] && {
            git -C "$DIR_SRC/redis2-nginx-module" pull origin master
        }; } || {
            git clone https://github.com/openresty/redis2-nginx-module.git
        }
        # srcache module
        { [ -d "$DIR_SRC/srcache-nginx-module" ] && {
            git -C "$DIR_SRC/srcache-nginx-module" pull origin master
        }; } || {
            git clone https://github.com/openresty/srcache-nginx-module.git
        }
        # set-misc module
        { [ -d "$DIR_SRC/set-misc-nginx-module" ] && {
            git -C "$DIR_SRC/set-misc-nginx-module" pull origin master
        }; } || {
            git clone https://github.com/openresty/set-misc-nginx-module.git
        }
        # auth_pam module
        { [ -d "$DIR_SRC/ngx_http_auth_pam_module" ] && {
            git -C "$DIR_SRC/ngx_http_auth_pam_module" pull origin master
        }; } || {
            git clone https://github.com/sto/ngx_http_auth_pam_module.git
        }
        # nginx-vts module
        { [ -d "$DIR_SRC/nginx-module-vts" ] && {
            git -C "$DIR_SRC/nginx-module-vts" pull origin master
        }; } || {
            git clone https://github.com/vozlt/nginx-module-vts.git
        }
        # http redis module
        [ ! -d /usr/local/src/ngx_http_redis ] && {
            curl -sL https://people.freebsd.org/~osa/ngx_http_redis-0.3.8.tar.gz | /bin/tar zxf - -C "$DIR_SRC"
            mv ngx_http_redis-0.3.8 ngx_http_redis
        }
        if [ "$RTMP" = "y" ]; then
            { [ -d "$DIR_SRC/nginx-rtmp-module" ] && {
                git -C "$DIR_SRC/nginx-rtmp-module" pull origin master
            }; } || {
                git clone https://github.com/arut/nginx-rtmp-module.git
            }
        fi

        # ipscrub module
        { [ -d "$DIR_SRC/ipscrubtmp" ] && {
            git -C "$DIR_SRC/ipscrubtmp" pull origin master
        }; } || {
            git clone https://github.com/masonicboom/ipscrub.git ipscrubtmp
        }

        echo "### additionals modules downloaded ###"
    } >> /tmp/nginx-ee.log 2>&1; then
        echo -ne "       Downloading additionals modules        [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "        Downloading additionals modules      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download zlib
##################################

_download_zlib() {

    echo -ne '       Downloading zlib                       [..]\r'

    if {
        cd "$DIR_SRC" || exit 1
        if [ "$OS_ARCH" = 'x86_64' ]; then
            { [ -d /usr/local/src/zlib-cf ] && {
                echo "### git pull zlib-cf ###"
                git -c /usr/local/src/zlib-cf pull
            }; } || {
                echo "### cloning zlib-cf ###"
                git clone https://github.com/cloudflare/zlib.git -b gcc.amd64 /usr/local/src/zlib-cf
            }
            cd /usr/local/src/zlib-cf || exit 1
            echo "### make distclean ###"
            make -f Makefile.in distclean
            echo "### configure zlib-cf ###"
            ./configure --prefix=/usr/local/zlib-cf
        else
            echo "### downloading zlib 1.2.11 ###"
            rm -rf zlib
            curl -sL http://zlib.net/zlib-1.2.11.tar.gz | /bin/tar zxf - -C "$DIR_SRC"
            mv zlib-1.2.11 zlib
        fi

    } >> /tmp/nginx-ee.log 2>&1; then
        echo -ne "       Downloading zlib                       [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading zlib                       [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download & compile pcre
##################################

_download_pcre() {

    cd "$DIR_SRC" || exit 1

    echo -ne '       Downloading pcre                       [..]\r'
    if {
        if [ -z "$(command -v pcretest)" ]; then
            {
                curl -sL https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VER}.tar.gz | /bin/tar zxf - -C "$DIR_SRC"
                mv pcre-${PCRE_VER} pcre

                cd "$DIR_SRC/pcre" || exit 1
                ./configure --prefix=/usr \
                    --enable-utf8 \
                    --enable-unicode-properties \
                    --enable-pcre16 \
                    --enable-pcre32 \
                    --enable-pcregrep-libz \
                    --enable-pcregrep-libbz2 \
                    --enable-pcretest-libreadline \
                    --enable-jit

                make -j "$(nproc)"
                make install
                mv -v /usr/lib/libpcre.so.* /lib
                ln -sfv ../../lib/"$(readlink /usr/lib/libpcre.so)" /usr/lib/libpcre.so

            } >> /tmp/nginx-ee.log 2>&1
        else
            PCRE_VERSION=$(pcretest -C 2>&1 | grep version | awk -F " " '{print $3}')
            if [ "$PCRE_VERSION" != "$PCRE_VER" ]; then

                {
                    curl -sL https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VER}.tar.gz | /bin/tar zxf - -C "$DIR_SRC"
                    mv pcre-${PCRE_VER} pcre

                    cd "$DIR_SRC/pcre" || exit 1
                    ./configure --prefix=/usr \
                        --enable-utf8 \
                        --enable-unicode-properties \
                        --enable-pcre16 \
                        --enable-pcre32 \
                        --enable-pcregrep-libz \
                        --enable-pcregrep-libbz2 \
                        --enable-pcretest-libreadline \
                        --enable-jit

                    make -j "$(nproc)"
                    make install
                    mv -v /usr/lib/libpcre.so.* /lib
                    ln -sfv ../../lib/"$(readlink /usr/lib/libpcre.so)" /usr/lib/libpcre.so

                } >> /tmp/nginx-ee.log 2>&1

            fi
        fi
    }; then
        echo -ne "       Downloading pcre                       [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading pcre                       [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download ngx_broti
##################################

_download_brotli() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading brotli                     [..]\r'
        {
            if [ -d "$DIR_SRC/ngx_brotli" ]; then
                git -C "$DIR_SRC/ngx_brotli" pull origin master
            else
                git clone --recursive https://github.com/eustas/ngx_brotli /usr/local/src/ngx_brotli -q
            fi
        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading brotli                     [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading brotli      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download and patch OpenSSL
##################################

_download_openssl_dev() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading openssl                    [..]\r'

        {
            if [ -d /usr/local/src/openssl ]; then
                if [ ! -d /usr/local/src/openssl/.git ]; then
                    echo "### removing openssl extracted archive ###"
                    rm -rf /usr/local/src/openssl
                    echo "### cloning openssl ###"
                    git clone https://github.com/openssl/openssl.git /usr/local/src/openssl
                    cd /usr/local/src/openssl || exit 1
                    echo "### git checkout commit ###"
                    git checkout $OPENSSL_COMMIT
                else
                    cd /usr/local/src/openssl || exit 1
                    echo "### reset openssl to master and clean patches ###"
                    git fetch --all
                    git reset --hard origin/master
                    git clean -f
                    git checkout $OPENSSL_COMMIT
                fi
            else
                echo "### cloning openssl ###"
                git clone https://github.com/openssl/openssl.git /usr/local/src/openssl
                cd /usr/local/src/openssl || exit 1
                echo "### git checkout commit ###"
                git checkout $OPENSSL_COMMIT
            fi
        } >> /tmp/nginx-ee.log 2>&1

        {
            if [ -d /usr/local/src/openssl-patch/.git ]; then
                cd /usr/local/src/openssl-patch || exit 1
                git pull origin master
            else
                git clone https://github.com/VirtuBox/openssl-patch.git /usr/local/src/openssl-patch
            fi
            cd /usr/local/src/openssl || exit 1
            # apply openssl ciphers patch
            echo "### openssl ciphers patch ###"
            patch -p1 < ../openssl-patch/openssl-equal-3.0.0-dev_ciphers.patch
        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading openssl                    [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading openssl      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download and patch OpenSSL
##################################

_download_openssl() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading openssl                    [..]\r'
        {
            rm -rf /usr/local/src/openssl
            curl -sL https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz | /bin/tar xzf - -C "$DIR_SRC"
            mv /usr/local/src/openssl-${OPENSSL_VER} /usr/local/src/openssl
        } >> /tmp/nginx-ee.log 2>&1

        {
            if [ -d /usr/local/src/openssl-patch/.git ]; then
                cd /usr/local/src/openssl-patch || exit 1
                git pull origin master
            else
                rm -rf /usr/local/src/openssl-patch
                git clone https://github.com/VirtuBox/openssl-patch.git /usr/local/src/openssl-patch
            fi
            cd /usr/local/src/openssl || exit 1
            # apply openssl ciphers patch
            echo "### openssl ciphers patch ###"
            patch -p1 < ../openssl-patch/openssl-equal-${OPENSSL_VER}_ciphers.patch
        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading openssl                    [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'

    else
        echo -e "       Downloading openssl      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download LibreSSL
##################################

_download_libressl() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading LibreSSL                   [..]\r'

        {
            rm -rf /usr/local/src/libressl
            curl -sL http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRESSL_VER}.tar.gz | /bin/tar xzf - -C "$DIR_SRC"
            mv /usr/local/src/libressl-${LIBRESSL_VER} /usr/local/src/libressl
        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading LibreSSL                   [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading LibreSSL      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download Naxsi
##################################

_download_naxsi() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading naxsi                      [..]\r'
        {

            git clone https://github.com/nbs-system/naxsi.git /usr/local/src/naxsi -q

            cp -f /usr/local/src/naxsi/naxsi_config/naxsi_core.rules /etc/nginx/naxsi_core.rules

        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading naxsi                      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading naxsi      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download Pagespeed
##################################

_download_pagespeed() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading pagespeed                  [..]\r'

        {
            wget -O build_ngx_pagespeed.sh https://raw.githubusercontent.com/pagespeed/ngx_pagespeed/master/scripts/build_ngx_pagespeed.sh
            chmod +x build_ngx_pagespeed.sh
            if [ "$PAGESPEED_RELEASE" = "1" ]; then
                ./build_ngx_pagespeed.sh --ngx-pagespeed-version latest-beta -b "$DIR_SRC"
            else
                ./build_ngx_pagespeed.sh --ngx-pagespeed-version latest-stable -b "$DIR_SRC"
            fi
        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading pagespeed                  [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading pagespeed                  [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
}

##################################
# Download Nginx
##################################

_download_nginx() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading nginx                      [..]\r'

        {
            rm -rf /usr/local/src/nginx
            curl -sL http://nginx.org/download/nginx-${NGINX_VER}.tar.gz | /bin/tar xzf - -C "$DIR_SRC"
            mv /usr/local/src/nginx-${NGINX_VER} /usr/local/src/nginx
        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading nginx                      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading nginx      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Apply Nginx patches
##################################

_patch_nginx() {

    cd /usr/local/src/nginx || exit 1
    if {
        echo -ne '       Applying nginx patches                 [..]\r'
        if [ "$NGINX_RELEASE" = "2" ]; then
            {
                curl -sL https://raw.githubusercontent.com/kn007/patch/master/nginx.patch | patch -p1
                curl -sL https://raw.githubusercontent.com/kn007/patch/master/nginx_auto_using_PRIORITIZE_CHACHA.patch | patch -p1
            } >> /tmp/nginx-ee.log 2>&1
        else
            {
                echo "### nginx_hpack_push patch"

                echo "### nginx_dynamic_tls_records patch"
                #            curl -sL https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.15.5%2B.patch | patch -p1
                #            curl -sL https://raw.githubusercontent.com/centminmod/centminmod/123.09beta01/patches/cloudflare/nginx-1.15.3_http2-hpack.patch | patch -p1
                curl -sL https://raw.githubusercontent.com/kn007/patch/master/nginx.patch | patch -p1
                curl -sL https://raw.githubusercontent.com/kn007/patch/master/nginx_auto_using_PRIORITIZE_CHACHA.patch | patch -p1
            } >> /tmp/nginx-ee.log 2>&1
        fi

    }; then
        echo -ne "       Applying nginx patches                 [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Applying nginx patches                 [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Configure Nginx
##################################

_configure_nginx() {

    if {
        echo -ne '       Configuring nginx                      [..]\r'

        # main configuration
        NGINX_BUILD_OPTIONS="--prefix=/usr/share \
--conf-path=/etc/nginx/nginx.conf \
--http-log-path=/var/log/nginx/access.log \
--error-log-path=/var/log/nginx/error.log \
--lock-path=/var/lock/nginx.lock \
--pid-path=/var/run/nginx.pid \
--http-client-body-temp-path=/var/lib/nginx/body \
--http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
--http-proxy-temp-path=/var/lib/nginx/proxy \
--http-scgi-temp-path=/var/lib/nginx/scgi \
--http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
--modules-path=/usr/share/nginx/modules"

        # built-in modules
        if [ -z "$OVERRIDE_NGINX_MODULES" ]; then
            if [ "$DYNAMIC_MODULES" = "y" ]; then
                NGINX_INCLUDED_MODULES="--with-http_stub_status_module \
        --with-http_realip_module \
        --with-http_auth_request_module \
        --with-http_addition_module \
        --with-http_gzip_static_module \
        --with-http_gunzip_module \
        --with-http_mp4_module \
        --with-http_sub_module
        --with-mail=dynamic \
        --with-stream=dynamic \
        --with-http_geoip_module=dynamic \
        --with-http_image_filter_module=dynamic "
            else
                NGINX_INCLUDED_MODULES="--with-http_stub_status_module \
        --with-http_realip_module \
        --with-http_auth_request_module \
        --with-http_addition_module \
        --with-http_gzip_static_module \
        --with-http_gunzip_module \
        --with-http_mp4_module \
        --with-http_sub_module"
            fi
        else
            NGINX_INCLUDED_MODULES="$OVERRIDE_NGINX_MODULES"
        fi

        # third party modules
        if [ -z "$OVERRIDE_NGINX_ADDITIONAL_MODULES" ]; then
            if [ "$DYNAMIC_MODULES" = "y" ]; then
                NGINX_THIRD_MODULES="--add-module=../ngx_http_substitutions_filter_module \
        --add-dynamic-module=../srcache-nginx-module \
        --add-dynamic-module=../ngx_http_redis \
        --add-dynamic-module=../redis2-nginx-module \
        --add-dynamic-module=../memc-nginx-module \
        --add-module=../ngx_devel_kit \
        --add-module=../set-misc-nginx-module \
        --add-dynamic-module=../ngx_http_auth_pam_module \
        --add-module=../nginx-module-vts \
        --add-dynamic-module=../ipscrubtmp/ipscrub"
            else
                NGINX_THIRD_MODULES="--add-module=../ngx_http_substitutions_filter_module \
        --add-module=../srcache-nginx-module \
        --add-module=../ngx_http_redis \
        --add-module=../redis2-nginx-module \
        --add-module=../memc-nginx-module \
        --add-module=../ngx_devel_kit \
        --add-module=../set-misc-nginx-module \
        --add-module=../ngx_http_auth_pam_module \
        --add-module=../nginx-module-vts \
        --add-module=../ipscrubtmp/ipscrub"
            fi
        else
            NGINX_THIRD_MODULES="$OVERRIDE_NGINX_ADDITIONAL_MODULES"
        fi

        if [ "$OS_ARCH" = 'x86_64' ]; then
            if [ "$DISTRO_ID" = "Ubuntu" ]; then
                ./configure \
                    ${NGX_NAXSI} \
                    --with-cc-opt='-m64 -march=native -mtune=native -DTCP_FASTOPEN=23 -g -O3 -fstack-protector-strong -flto -ffat-lto-objects -fuse-ld=gold --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Wimplicit-fallthrough=0 -fcode-hoisting -Wp,-D_FORTIFY_SOURCE=2 -gsplit-dwarf' \
                    --with-ld-opt='-lrt -ljemalloc -Wl,-z,relro -Wl,-z,now -fPIC -flto -ffat-lto-objects' \
                    ${NGINX_BUILD_OPTIONS} \
                    --build='VirtuBox Nginx-ee' \
                    ${NGX_USER} \
                    --with-file-aio \
                    --with-threads \
                    ${NGX_HPACK} \
                    --with-http_v2_module \
                    --with-http_ssl_module \
                    --with-pcre-jit \
                    ${NGINX_INCLUDED_MODULES} \
                    ${NGINX_THIRD_MODULES} \
                    ${NGX_PAGESPEED} \
                    ${NGX_RTMP} \
                    --add-module=../echo-nginx-module \
                    --add-module=../headers-more-nginx-module \
                    --add-module=../ngx_cache_purge \
                    --add-module=../ngx_brotli \
                    --with-zlib=../zlib-cf \
                    ${NGX_SSL_LIB} \
                    --with-openssl-opt="$OPENSSL_OPT" \
                    --sbin-path=/usr/sbin/nginx >> /tmp/nginx-ee.log 2>&1
            else

                ./configure \
                    --with-cc-opt="$DEB_CFLAGS" \
                    --with-ld-opt="$DEB_LFLAGS" \
                    ${NGX_NAXSI} \
                    ${NGINX_BUILD_OPTIONS} \
                    --build='VirtuBox Nginx-ee' \
                    ${NGX_USER} \
                    --with-file-aio \
                    --with-threads \
                    ${NGX_HPACK} \
                    --with-http_v2_module \
                    --with-http_ssl_module \
                    --with-pcre-jit \
                    ${NGINX_INCLUDED_MODULES} \
                    ${NGINX_THIRD_MODULES} \
                    ${NGX_PAGESPEED} \
                    ${NGX_RTMP} \
                    --add-module=../echo-nginx-module \
                    --add-module=../headers-more-nginx-module \
                    --add-module=../ngx_cache_purge \
                    --add-module=../ngx_brotli \
                    --with-zlib=../zlib-cf \
                    ${NGX_SSL_LIB} \
                    --with-openssl-opt="$OPENSSL_OPT" \
                    --sbin-path=/usr/sbin/nginx >> /tmp/nginx-ee.log 2>&1
            fi
        else

            ./configure \
                ${NGX_NAXSI} \
                --with-cc-opt="$DEB_CFLAGS" \
                --with-ld-opt="$DEB_LFLAGS" \
                ${NGINX_BUILD_OPTIONS} \
                --build='VirtuBox Nginx-ee' \
                ${NGX_USER} \
                --with-file-aio \
                --with-threads \
                --with-http_v2_module \
                --with-http_ssl_module \
                --with-pcre-jit \
                ${NGINX_INCLUDED_MODULES} \
                ${NGINX_THIRD_MODULES} \
                ${NGX_HPACK} \
                ${NGX_PAGESPEED} \
                ${NGX_RTMP} \
                --add-module=../echo-nginx-module \
                --add-module=../headers-more-nginx-module \
                --add-module=../ngx_cache_purge \
                --add-module=../ngx_brotli \
                --with-zlib=../zlib \
                ${NGX_SSL_LIB} \
                --with-openssl-opt="$OPENSSL_OPT" \
                --sbin-path=/usr/sbin/nginx >> /tmp/nginx-ee.log 2>&1
        fi

    }; then
        echo -ne "       Configuring nginx                      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "        Configuring nginx    [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Compile Nginx
##################################

_compile_nginx() {
    if {
        echo -ne '       Compiling nginx                        [..]\r'

        {
            make -j "$(nproc)"
            make install

        } >> /tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Compiling nginx                        [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Compiling nginx                        [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Perform final tasks
##################################

_updating_nginx_manual() {

    echo -ne '       Updating Nginx manual                  [..]\r'
    if {
        # update nginx manual
        [ -f /usr/share/man/man8/nginx.8.gz ] && {
            rm /usr/share/man/man8/nginx.8.gz
        }

        {
            cp -f ${DIR_SRC}/nginx/man/nginx.8 /usr/share/man/man8
            gzip /usr/share/man/man8/nginx.8

        } >> /tmp/nginx-ee.log

        # update mime.types
        cp -f ${DIR_SRC}/nginx/conf/mime.types /etc/nginx/mime.types

    }; then
        echo -ne "       Updating Nginx manual                  [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Updating Nginx manual                  [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

_cron_setup() {
    echo -ne '       Installing Nginx-ee Cronjob            [..]\r'
    if {
        wget -O /etc/cron.daily/nginx-ee https://raw.githubusercontent.com/VirtuBox/nginx-ee/develop/etc/cron.daily/nginx-ee >> /tmp/nginx-ee.log
        chmod +x /etc/cron.daily/nginx-ee

    }; then
        echo -ne "       Installing Nginx-ee Cronjob            [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Installing Nginx-ee Cronjob            [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

_final_tasks() {

    echo -ne '       Performing final steps                 [..]\r'
    if {
        # block Nginx package update from APT repository
        if [ "$NGINX_PLESK" = "1" ]; then
            {
                # update nginx ciphers_suites
                sed -i "s/ssl_ciphers\ \(\"\|.\|'\)\(.*\)\(\"\|.\|'\);/ssl_ciphers \"$TLS13_CIPHERS\";/" /etc/nginx/conf.d/ssl.conf
                # update nginx ssl_protocols
                sed -i "s/ssl_protocols\ \(.*\);/ssl_protocols TLSv1.2 TLSv1.3;/" /etc/nginx/conf.d/ssl.conf
                # block sw-nginx package updates from APT repository
                echo -e 'Package: sw-nginx*\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/nginx-block
                apt-mark hold sw-nginx
            } >> /tmp/nginx-ee.log
        elif [ "$NGINX_EASYENGINE" = "1" ]; then
            {
                # update nginx ssl_protocols
                sed -i "s/ssl_protocols\ \(.*\);/ssl_protocols TLSv1.2 TLSv1.3;/" /etc/nginx/nginx.conf
                # update nginx ciphers_suites
                sed -i "s/ssl_ciphers\ \(\"\|'\)\(.*\)\(\"\|'\)/ssl_ciphers \"$TLS13_CIPHERS\"/" /etc/nginx/nginx.conf
                # block nginx package updates from APT repository
                echo -e 'Package: nginx*\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/nginx-block
                apt-mark hold nginx-ee nginx-common nginx-custom
            } >> /tmp/nginx-ee.log
        elif [ "$WO_VALID" = "1" ]; then
            {
                # update nginx ssl_protocols
                sed -i "s/ssl_protocols\ \(.*\);/ssl_protocols TLSv1.2 TLSv1.3;/" /etc/nginx/nginx.conf
                # update nginx ciphers_suites
                sed -i "s/ssl_ciphers\ \(\"\|.\|'\)\(.*\)\(\"\|.\|'\);/ssl_ciphers \"$TLS13_CIPHERS\";/" /etc/nginx/nginx.conf
                # block nginx package updates from APT repository
                echo -e 'Package: nginx*\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/nginx-block
                CHECK_NGINX_WO=$(dpkg --list | grep nginx-wo)
                if [ -z "$CHECK_NGINX_WO" ]; then
                    apt-mark hold nginx-wo nginx-common nginx-custom
                else
                    apt-mark hold nginx-ee nginx-common nginx-custom
                fi
            } >> /tmp/nginx-ee.log
        fi

        {
            # enable nginx service
            systemctl unmask nginx.service
            systemctl enable nginx.service
            systemctl start nginx.service
            # remove default configuration
            rm -f /etc/nginx/{*.default,*.dpkg-dist}
        } > /dev/null 2>&1

    }; then
        echo -ne "       Performing final steps                 [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Performing final steps                 [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

    echo -ne '       Checking nginx configuration           [..]\r'

    # check if nginx -t do not return errors
    VERIFY_NGINX_CONFIG=$(nginx -t 2>&1 | grep failed)
    if [ -z "$VERIFY_NGINX_CONFIG" ]; then
        {
            systemctl stop nginx
            systemctl start nginx
        } >> /tmp/nginx-ee.log 2>&1
        echo -ne "       Checking nginx configuration           [${CGREEN}OK${CEND}]\\r"
        echo ""
        echo -e "       ${CGREEN}Nginx-ee was compiled successfully !${CEND}"
        echo -e '\n       Installation log : /tmp/nginx-ee.log\n'
    else
        echo -e "       Checking nginx configuration           [${CRED}FAIL${CEND}]"
        echo -e "       Nginx-ee was compiled successfully but there is an error in your nginx configuration"
        echo -e '\nPlease look at /tmp/nginx-ee.log or use the command nginx -t to find the issue\n'
    fi

}

##################################
# Main Setup
##################################

_install_dependencies
if [ "$NGINX_FROM_SCRATCH" = "1" ]; then
    _nginx_from_scratch_setup
fi
if [ "$DISTRO_ID" = "Ubuntu" ]; then
    _gcc_ubuntu_setup
fi
if [ "$RTMP" = "y" ]; then
    _rtmp_setup
fi
_cleanup_modules
_download_modules
_download_zlib
_download_pcre
_download_brotli
if [ "$NAXSI" = "y" ]; then
    _download_naxsi
fi
if [ "$LIBRESSL" = "y" ]; then
    _download_libressl
else
    if [ "$OPENSSL_LIB" = "2" ]; then
        _download_openssl_dev
    elif [ "$OPENSSL_LIB" = "3" ]; then
        sleep 1
    else
        _download_openssl
    fi
fi
if [ "$PAGESPEED" = "y" ]; then
    _download_pagespeed
fi
_download_nginx
_patch_nginx
_configure_nginx
_compile_nginx
_updating_nginx_manual
if [ "$CRON_SETUP" = "y" ]; then
    _cron_setup
fi
_final_tasks
