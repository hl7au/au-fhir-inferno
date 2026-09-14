# Pinned (was nginx:latest) for reproducible builds — bump deliberately.
#
# On the stable branch (1.30.x) rather than mainline (1.31.x): this image is pinned
# per release and promoted explicitly, so it wants fixes without features. The 1.27
# branch is frozen upstream, receiving neither nginx fixes nor Debian base rebuilds,
# and predates the CVE-2026-42533 fix (map regex capture clobbering, first fixed in
# 1.30.4 stable / 1.31.3 mainline).
FROM nginx:1.30.4
COPY ./_site /var/www/inferno/public/
COPY ./nginx.conf /etc/nginx/nginx.conf