// A tiny stand-in for the organisation's own service, so the samples that need an API (docs/sample-forms/needs-setup/) can be tried: a list at /list and a Get API at /person.
//   node tools/sample-forms/stand-in-api.mjs [port]        (default 8765; it answers on 127.0.0.1)
// The Connectum server must be able to reach it: a server on your own machine can; the shared servers refuse private addresses unless CONNECTUM_API_ALLOW_PRIVATE=1 is set. The answers
// are the standard ones: { status: "ok", rows: [...] } for a list and { status: "ok", data: {...} } for one record (data: null means nobody was found).
import http from "node:http";
import { fileURLToPath } from "node:url";

export const LIST = [{ id: "a", name: "Alpha" }, { id: "b", name: "Beta" }, { id: "c", name: "Gamma" }];
export const PERSON = { Employee_Name: "Asha Rao", city: "Pune" };

export function startStandInApi(port = 0) {
  const server = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", () => {
      let body = {}; try { body = JSON.parse(raw); } catch { /* none */ }
      const json = (code, o) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(o)); };
      if (req.url.startsWith("/list")) return json(200, { status: "ok", rows: LIST });
      if (req.url.startsWith("/person")) return body.params?.code === "NONE" ? json(200, { status: "ok", data: null }) : json(200, { status: "ok", data: PERSON });
      json(404, {});
    });
  });
  return new Promise((resolve) => server.listen(port, "127.0.0.1", () => resolve({ server, port: server.address().port })));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { port } = await startStandInApi(Number(process.argv[2]) || 8765);
  console.log(`stand-in API on http://127.0.0.1:${port}  (/list, /person)`);
}
