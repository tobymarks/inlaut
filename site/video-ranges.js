// Serves byte ranges for /video/* (Safari only plays MP4 that answers Range with 206).
// Static assets alone always answer 200 with the whole file; everything else goes straight to them.
export default {
  async fetch(request, env) {
    const range = request.headers.get("Range");
    if (!range || request.method !== "GET") return withRanges(await env.ASSETS.fetch(request));

    const full = await env.ASSETS.fetch(new Request(request.url, { method: "GET" }));
    if (full.status !== 200) return full;
    const body = await full.arrayBuffer();
    const size = body.byteLength;

    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    let start, end;
    if (m && m[1] !== "") {
      start = Number(m[1]);
      end = m[2] === "" ? size - 1 : Math.min(Number(m[2]), size - 1);
    } else if (m && m[2] !== "") {
      start = Math.max(0, size - Number(m[2]));
      end = size - 1;
    }
    if (start === undefined || start > end || start >= size) {
      return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${size}` } });
    }

    const headers = new Headers(full.headers);
    headers.set("Content-Range", `bytes ${start}-${end}/${size}`);
    headers.set("Content-Length", String(end - start + 1));
    headers.set("Accept-Ranges", "bytes");
    return new Response(body.slice(start, end + 1), { status: 206, headers });
  },
};

function withRanges(response) {
  const r = new Response(response.body, response);
  r.headers.set("Accept-Ranges", "bytes");
  return r;
}
