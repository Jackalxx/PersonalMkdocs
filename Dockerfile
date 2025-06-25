FROM python:3.11-alpine3.21

# 安裝依賴工具，避免部分套件編譯失敗
RUN apk add --no-cache build-base libffi-dev musl-dev

WORKDIR /docs

# 安裝套件
COPY pippkg.txt .
RUN pip install --no-cache-dir -r pippkg.txt

# 確保已安裝 mkdocs（如果沒寫進 pippkg.txt）
RUN pip install --no-cache-dir mkdocs

EXPOSE 8000

CMD ["mkdocs", "serve", "-a", "0.0.0.0:8000"]



# # 暫時參考github專案建置方案, 後續要拆兩段
# # 1. 抓指定版本的python鏡像檔, 安裝完套件後推送到本地鏡像庫
# # 2. 從本地鏡像庫抓建置好的鏡像檔為runtime, 複製目錄後 建置並運行
# # 只有需要更新套件時才必須要手動重跑流程1, 平時更新內容只需要跑2

# FROM python:3.11-alpine3.21 AS build

# # Build-time flags
# ARG WITH_PLUGINS=true

# # Environment variables
# ENV PACKAGES=/usr/local/lib/python3.11/site-packages
# ENV PYTHONDONTWRITEBYTECODE=1

# # Set build directory
# WORKDIR /tmp

# # Copy files necessary for build
# COPY material material
# COPY package.json package.json
# COPY README.md README.md
# COPY *requirements.txt ./
# COPY pyproject.toml pyproject.toml

# # Perform build and cleanup artifacts and caches
# RUN \
#   apk upgrade --update-cache -a \
# && \
#   apk add --no-cache \
#     cairo \
#     freetype-dev \
#     git \
#     git-fast-import \
#     jpeg-dev \
#     openssh \
#     tini \
#     zlib-dev \
# && \
#   apk add --no-cache --virtual .build \
#     gcc \
#     g++ \
#     libffi-dev \
#     musl-dev \
# && \
#   pip install --no-cache-dir --upgrade pip \
# && \
#   pip install --no-cache-dir . \
# && \
#   if [ "${WITH_PLUGINS}" = "true" ]; then \
#     pip install --no-cache-dir \
#       mkdocs-material[recommended] \
#       mkdocs-material[imaging]; \
#   fi \
# && \
#   if [ -e user-requirements.txt ]; then \
#     pip install -U -r user-requirements.txt; \
#   fi \
# && \
#   apk del .build \
# && \
#   for theme in mkdocs readthedocs; do \
#     rm -rf ${PACKAGES}/mkdocs/themes/$theme; \
#     ln -s \
#       ${PACKAGES}/material/templates \
#       ${PACKAGES}/mkdocs/themes/$theme; \
#   done \
# && \
#   rm -rf /tmp/* /root/.cache \
# && \
#   find ${PACKAGES} \
#     -type f \
#     -path "*/__pycache__/*" \
#     -exec rm -f {} \; \
# && \
#   git config --system --add safe.directory /docs \
# && \
#   git config --system --add safe.directory /site

# #  From empty image
# FROM scratch

# # Copy all from build
# COPY --from=build / /

# # Set working directory
# WORKDIR /docs

# # Expose MkDocs development server port
# EXPOSE 8000

# # Start development server by default
# ENTRYPOINT ["/sbin/tini", "--", "mkdocs"]
# CMD ["serve", "--dev-addr=0.0.0.0:8000"]