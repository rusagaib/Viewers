# syntax=docker/dockerfile:1.7-labs

# ============================================================
# Stage 1: Build OHIF
# ============================================================
FROM node:20.20.0-slim AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        python3 \
        curl \
        unzip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Bun dibutuhkan oleh beberapa script OHIF
RUN curl -fsSL https://bun.sh/install | bash

ENV PATH="/root/.bun/bin:/usr/src/app/node_modules/.bin:${PATH}"

# Lerna
RUN npm install -g lerna@9.0.4

RUN node --version \
    && npm --version \
    && bun --version \
    && yarn --version \
    && lerna --version

# ============================================================
# COPY SELURUH REPOSITORY
# ============================================================
COPY . .

# ============================================================
# INSTALL DENGAN YARN
# ============================================================
RUN yarn config set workspaces-experimental true
RUN yarn install --frozen-lockfile

# ============================================================
# DEBUG
# ============================================================
RUN echo "=== BUILD DEPENDENCIES ===" \
    && node -p "require('./node_modules/webpack/package.json').version" \
    && node -p "require('./node_modules/cross-env/package.json').version" \
    && ls -lah node_modules/.bin/webpack \
    && ls -lah node_modules/.bin/cross-env

# ============================================================
# BUILD
# ============================================================
# ENV QUICK_BUILD=true

ARG APP_CONFIG=config/default.js
ARG PUBLIC_URL=/

ENV PUBLIC_URL=${PUBLIC_URL}

ENV GENERATE_SOURCEMAP=false

RUN yarn run show:config

RUN yarn build

# ============================================================
# PRECOMPRESS
# ============================================================
RUN chmod u+x .docker/compressDist.sh \
    && ./.docker/compressDist.sh


# ============================================================
# Stage 2: Nginx
# ============================================================
FROM nginxinc/nginx-unprivileged:1.27-alpine AS final

ARG PUBLIC_URL=/
ENV PUBLIC_URL=${PUBLIC_URL}

ARG PORT=80
ENV PORT=${PORT}


RUN rm /etc/nginx/conf.d/default.conf


USER nginx

COPY --chown=nginx:nginx \
    .docker/Viewer-v3.x \
    /usr/src


RUN chmod 777 /usr/src/entrypoint.sh


COPY --from=builder \
    /usr/src/app/platform/app/dist \
    /usr/share/nginx/html${PUBLIC_URL}


# Microscopy viewer needs to exist at root
COPY --from=builder \
    /usr/src/app/platform/app/dist/dicom-microscopy-viewer \
    /usr/share/nginx/html/dicom-microscopy-viewer


USER root

RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chmod -R 777 /usr/share/nginx/html


USER nginx

ENTRYPOINT ["/usr/src/entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]

