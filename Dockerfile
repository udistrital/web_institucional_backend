FROM php:8.3-fpm-alpine

RUN apk add --no-cache nginx git unzip \
    libpng-dev libjpeg-turbo-dev freetype-dev \
    && docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install gd pdo pdo_mysql opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-interaction

COPY . .
RUN mkdir -p web/sites/default/files web/sites/default/private \
    && chown -R www-data:www-data web/sites/default/files web/sites/default/private \
    && chmod -R 755 web/sites/default/files web/sites/default/private
COPY docker/nginx.conf /etc/nginx/http.d/default.conf

EXPOSE 80
CMD ["sh", "-c", "php-fpm -D && nginx -g 'daemon off;'"]