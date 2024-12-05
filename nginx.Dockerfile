FROM nginx:latest
COPY ./_site /var/www/inferno/public/
COPY ./nginx.conf /etc/nginx/nginx.conf