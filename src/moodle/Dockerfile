FROM bitnamilegacy/moodle:latest

USER root

# 1. Configurar repositorio oficial de PHP (Sury) para obtener versión parcheada contra PHP2Shell
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates lsb-release gnupg \
    && curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb \
    && dpkg -i /tmp/debsuryorg-archive-keyring.deb \
    && echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        php8.3-cli \
        php8.3-fpm \
        libapache2-mod-php8.3 \
        php8.3-mysql \
        php8.3-xml \
        php8.3-curl \
        php8.3-zip \
        php8.3-gd \
        php8.3-intl \
        php8.3-mbstring \
        php8.3-soap \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

# 2. Redirigir las rutas internas de Bitnami al nuevo PHP 8.3 parcheado (CLI y FPM)
RUN rm -f /opt/bitnami/php/bin/php \
    && ln -s /usr/bin/php8.3 /opt/bitnami/php/bin/php \
    && rm -f /usr/bin/php \
    && ln -s /usr/bin/php8.3 /usr/bin/php \
    && if [ -d /opt/bitnami/php/sbin ]; then \
        rm -f /opt/bitnami/php/sbin/php-fpm \
        && ln -s /usr/sbin/php-fpm8.3 /opt/bitnami/php/sbin/php-fpm; \
    fi

# 3. Creamos enlace simbólico para el plugin BDC
RUN ln -s /moodle-custom-plugin /opt/bitnami/moodle/blocks/bdc

# Volvemos al usuario sin privilegios por seguridad
USER 1001
