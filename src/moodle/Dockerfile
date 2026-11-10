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

# 3. Aumentar max_input_vars a 6000 (necesario para formularios grandes de Moodle)
RUN for ini in \
        /etc/php/8.3/apache2/php.ini \
        /etc/php/8.3/cli/php.ini \
        /etc/php/8.3/fpm/php.ini \
        /opt/bitnami/php/etc/php.ini; \
    do \
        if [ -f "$ini" ]; then \
            sed -i 's/^;\?\s*max_input_vars\s*=.*/max_input_vars = 6000/' "$ini"; \
        fi; \
    done \
    && echo "max_input_vars = 6000" > /etc/php/8.3/apache2/conf.d/99-max-input-vars.ini 2>/dev/null || true \
    && echo "max_input_vars = 6000" > /etc/php/8.3/cli/conf.d/99-max-input-vars.ini 2>/dev/null || true \
    && echo "max_input_vars = 6000" > /etc/php/8.3/fpm/conf.d/99-max-input-vars.ini 2>/dev/null || true \
    && mkdir -p /opt/bitnami/php/etc/conf.d \
    && echo "max_input_vars = 6000" > /opt/bitnami/php/etc/conf.d/99-max-input-vars.ini

# 4. Creamos enlace simbólico para el plugin BDC
RUN ln -s /moodle-custom-plugin /opt/bitnami/moodle/blocks/bdc

# 5. Asegurar que Moodle wwwroot use dinámicamente MOODLE_URL en cada inicio (Issues #2 y #4)
COPY fix_wwwroot.php /opt/bitnami/scripts/moodle/fix_wwwroot.php
RUN echo 'php /opt/bitnami/scripts/moodle/fix_wwwroot.php || true' >> /opt/bitnami/scripts/moodle/setup.sh
