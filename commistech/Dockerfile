# ─────────────────────────────────────────────────────────
#  Commis Tech — Dockerfile (ECS / App Runner / EC2 option)
#  Build:  docker build -t commistech-web .
#  Run:    docker run -p 80:80 commistech-web
#  Push:   docker tag commistech-web <account>.dkr.ecr.<region>.amazonaws.com/commistech-web
# ─────────────────────────────────────────────────────────

FROM nginx:1.27-alpine

# Remove default nginx content
RUN rm -rf /usr/share/nginx/html/*

# Copy website files
COPY index.html   /usr/share/nginx/html/
COPY nginx-docker.conf /etc/nginx/conf.d/default.conf

# Non-root user for security
RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup && \
    chown -R appuser:appgroup /usr/share/nginx/html && \
    chown -R appuser:appgroup /var/cache/nginx && \
    chown -R appuser:appgroup /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown appuser:appgroup /var/run/nginx.pid

USER appuser

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
