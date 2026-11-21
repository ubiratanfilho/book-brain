import { afterEach, expect, test } from "bun:test";
import { answer } from "./agent.mjs";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

function stream(block, delta, reason) {
  const events = [
    { type: "message_start", message: { id: "msg_test", type: "message", role: "assistant",
      content: [], usage: { input_tokens: 10, output_tokens: 0 } } },
    { type: "content_block_start", index: 0, content_block: block },
    { type: "content_block_delta", index: 0, delta },
    { type: "content_block_stop", index: 0 },
    { type: "message_delta", delta: { stop_reason: reason }, usage: { output_tokens: 5 } },
    { type: "message_stop" },
  ];
  return new Response(events.map(e => "event: " + e.type + "\ndata: " + JSON.stringify(e) + "\n\n").join(""),
    { headers: { "content-type": "text/event-stream" } });
}

const request = {
  provider: "anthropic", model: "claude-sonnet-4-5", key: "synthetic-test-key",
  prompt: "Where are triangles defined?", instructions: "Use the supplied PDF.", callLimit: 16,
  inputs: [{ type: "image", url: "data:image/png;base64,iVBORw0KGgo=" }],
  tools: [{ name: "read_book_page", description: "Read a page", inputSchema: {
    type: "object", properties: { page: { type: "integer" } }, required: ["page"],
  }}],
};

test("Pi sends the screenshot, reads a PDF page, and streams the final answer", async () => {
  const requests = [];
  globalThis.fetch = async (url, options) => {
    const req = new Request(url, options);
    requests.push(await req.json());
    if (requests.length === 1) {
      return stream({ type: "tool_use", id: "tool_1", name: "read_book_page", input: {} },
        { type: "input_json_delta", partial_json: '{"page":2}' }, "tool_use");
    }
    return stream({ type: "text", text: "" }, { type: "text_delta", text: "See PDF p. 2." }, "end_turn");
  };
  const calls = [];
  const events = [];
  await answer(request, async (name, args) => {
    calls.push([name, args]);
    return { items: [{ type: "inputText", text: "PDF p. 2: A triangle has three sides." }] };
  }, event => events.push(event));
  expect(requests).toHaveLength(2);
  expect(requests[0].messages[0].content.some(block => block.type === "image")).toBe(true);
  expect(requests[0].tools.map(tool => tool.name)).toEqual(["read_book_page"]);
  expect(calls).toEqual([["read_book_page", { page: 2 }]]);
  expect(JSON.stringify(requests[1].messages)).toContain("A triangle has three sides.");
  expect(events).toContainEqual({ type: "delta", text: "See PDF p. 2." });
  expect(events.at(-1)).toEqual({ type: "done", text: "See PDF p. 2." });
});

test("provider error bodies stay out of chat errors", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({
    type: "error", error: { type: "authentication_error", message: request.key }
  }), { status: 401, headers: { "Content-Type": "application/json" } });
  await expect(answer(request, () => {}, () => {})).rejects.toThrow("Check your API key");
});

for (const [provider, model, host] of [
  ["openai", "gpt-4o", "api.openai.com"],
  ["google", "gemini-2.5-flash", "generativelanguage.googleapis.com"],
]) {
  test(provider + " routes requests to the selected provider with the supplied API key", async () => {
    const seen = [];
    globalThis.fetch = async (url, options) => {
      const req = new Request(url, options);
      seen.push({ host: new URL(req.url).hostname,
        auth: req.headers.get("authorization") ?? req.headers.get("x-goog-api-key") });
      return new Response('{"error":{"message":"synthetic rejection"}}', {
        status: 403, headers: { "content-type": "application/json" },
      });
    };
    await expect(answer({ ...request, provider, model }, () => {}, () => {}))
      .rejects.toThrow("Check your API key");
    expect(seen).toEqual([{ host, auth: provider === "openai" ? "Bearer " + request.key : request.key }]);
  });
}
