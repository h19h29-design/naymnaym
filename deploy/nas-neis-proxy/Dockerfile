FROM denoland/deno:alpine-2.9.6@sha256:aa665f8777136863b5b8a0445a5cdfccff8103b5f40c9a877de5276b04facb1e

WORKDIR /app
COPY supabase/functions/_shared/neis-contract/ supabase/functions/_shared/neis-contract/
COPY supabase/functions/neis-proxy/handler.ts supabase/functions/neis-proxy/
COPY supabase/functions/neis-proxy/neis-normalizer.ts supabase/functions/neis-proxy/
COPY supabase/functions/neis-proxy/origin-config.ts supabase/functions/neis-proxy/
COPY supabase/functions/neis-proxy/server.ts supabase/functions/neis-proxy/
COPY supabase/functions/neis-proxy/nas-main.ts supabase/functions/neis-proxy/
RUN deno cache supabase/functions/neis-proxy/nas-main.ts

USER 1000:1000
EXPOSE 8000
CMD ["run", "--cached-only", "--no-prompt", "--allow-env=NEIS_API_KEY,NEIS_ALLOWED_ORIGINS,NEIS_CLIENT_TOKEN", "--allow-net=0.0.0.0:8000,open.neis.go.kr:443", "supabase/functions/neis-proxy/nas-main.ts"]
