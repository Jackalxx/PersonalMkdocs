FROM python:3.11-alpine3.21

# 安裝依賴工具，避免部分套件編譯失敗
RUN apk add --no-cache build-base libffi-dev musl-dev

WORKDIR /docs

# 安裝套件
COPY pippkg.txt .
RUN pip install --no-cache-dir -r pippkg.txt

EXPOSE 8000

CMD ["mkdocs", "serve", "-a", "0.0.0.0:8000"]