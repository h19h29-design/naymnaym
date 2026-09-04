type BusinessHandler = (request: Request) => Response | Promise<Response>;

function plainError(status: number): Response {
  return new Response(null, {
    status,
    headers: {
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

export function createServerHandler(businessHandler: BusinessHandler) {
  return (request: Request): Response | Promise<Response> => {
    const { pathname } = new URL(request.url);
    if (pathname === "/health") {
      if (request.method !== "GET") return plainError(405);
      return new Response(JSON.stringify({ ok: true }), {
        headers: {
          "cache-control": "no-store",
          "content-type": "application/json; charset=utf-8",
          "x-content-type-options": "nosniff",
        },
      });
    }
    if (pathname !== "/") return plainError(404);
    return businessHandler(request);
  };
}
