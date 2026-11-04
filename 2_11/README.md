# Exercise 2.11 - My development environment

## Project

I containerized the development environment of my own project, **SentinAI**, a self-healing DevOps agent written in Python (FastAPI). The code lives in https://github.com/Ebencode-x/sentinai-project, branch `dev-container`:

- `Dockerfile.dev`
- `docker-compose.dev.yml`

The project already had a production `Dockerfile` and `docker-compose.yml` (multi-stage image, non-root user). I did not touch them. The development setup is separate so that the production image stays small and fixed.

## What I did

### `Dockerfile.dev`

```dockerfile
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV PIP_DEFAULT_TIMEOUT=120
ENV PIP_RETRIES=10
WORKDIR /app
COPY requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
EXPOSE 7860
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "7860", "--reload", "--reload-dir", "src", "--reload-dir", "sentinai"]
```

- Only the dependencies are baked into the image. The source code is not copied, it is bind mounted at runtime.
- uvicorn runs with `--reload`, so the server restarts when a file changes.
- The pip cache is kept between builds, so a failed or slow download can resume instead of starting from zero.

### `docker-compose.dev.yml`

```yaml
services:
  sentinai:
    build:
      context: .
      dockerfile: Dockerfile.dev
    env_file:
      - .env
    environment:
      DATABASE_URL: postgresql+psycopg2://sentinai:sentinai@postgres:5432/sentinai
    volumes:
      - ./:/app
    ports:
      - "8000:7860"
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: sentinai
      POSTGRES_PASSWORD: sentinai
      POSTGRES_DB: sentinai
    volumes:
      - sentinai-dev-pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sentinai -d sentinai"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  sentinai-dev-pgdata:
```

- `./:/app` is a bind mount: I edit the code on my machine and the container sees it immediately.
- Postgres runs as a container with a named volume, so nothing is installed on the host and the data survives `docker compose down`.
- The app waits for Postgres with a healthcheck (`service_healthy`).
- Secrets (API keys) are not in the compose file. They are read from `.env`, which is git-ignored.
- The Postgres password in the file is for local development only, and the Postgres port is not published to the host.

## How to use it

```
docker compose -f docker-compose.dev.yml up --build
```

The API is then available at http://localhost:8000/health/live.

## Result

- `curl localhost:8000/health/live` returned `{"status":"ok","service":"sentinai"}`.
- Hot reload works. After I appended a comment to `src/main.py`, the logs showed `WatchFiles detected changes in 'src/main.py'. Reloading...` and the server restarted by itself. Reverting the change triggered a second reload.

## Problems I had

1. **Port already allocated.** My exercise 2.8-2.10 stack was still using host port 8000, so Docker refused to start SentinAI (`Bind for 0.0.0.0:8000 failed: port is already allocated`). I stopped that stack with `docker compose down`.
2. **Slow network during `pip install`.** The build failed after about 20 minutes with `ReadTimeoutError` from files.pythonhosted.org. I raised `PIP_DEFAULT_TIMEOUT` and `PIP_RETRIES`, added the pip cache mount, and retried the build in a loop until it finished.
3. **`could not translate host name "postgres"`.** After the failed start from problem 1, the app could not resolve the database host. The compose network was left in a bad state. `docker compose down` followed by `up` recreated it and the error disappeared.
