# Pinned (was nginx:latest) for reproducible builds — bump deliberately.
FROM nginx:1.27
COPY ./_site /var/www/inferno/public/
COPY ./nginx.conf /etc/nginx/nginx.conf