import { Agent } from "@earendil-works/pi-agent-core";
import { createModels } from "@earendil-works/pi-ai/models";
import { anthropicProvider } from "@earendil-works/pi-ai/providers/anthropic";
import { googleProvider } from "@earendil-works/pi-ai/providers/google";
import { openaiProvider } from "@earendil-works/pi-ai/providers/openai";
import { createInterface } from "node:readline";

const models = createModels();
for (const provider of [anthropicProvider(), googleProvider(), openaiProvider()]) {
  models.setProvider(provider);
}

function image(url, model) {
  if (!model.input.includes("image")) {
    throw new ReaderError("Select a model with image support for screenshots or scanned pages.");
  }
  const match = /^data:(image\/(?:png|jpeg));base64,/.exec(url);
  if (!match) throw new ReaderError("Could not read the attached image.");
  return { type: "image", mimeType: match[1], data: url.slice(match[0].length) };
}

class ReaderError extends Error {}

export async function answer(request, callPDF, emit) {
  const model = models.getModel(request.provider, request.model);
  if (!model) throw new ReaderError("Choose a model from the installed catalog.");
  const content = [{ type: "text", text: request.prompt }];
  for (const input of request.inputs) {
    content.push(input.type === "text" ? input : image(input.url, model));
  }
  const tools = request.tools.map(({ name, description, inputSchema }) => ({
    name, label: name, description, parameters: inputSchema,
    async execute(_id, args) {
      const result = await callPDF(name, args);
      if (result.error) throw new Error(result.error);
      return {
        content: result.items.map(item => item.type === "inputImage"
          ? image(item.imageUrl, model) : { type: "text", text: item.text }),
        details: {},
      };
    },
  }));
  let requests = 0;
  const agent = new Agent({
    initialState: { model, systemPrompt: request.instructions, tools },
    toolExecution: "sequential",
    getApiKey: () => request.key,
    streamFn(model, context, options) {
      if (++requests > request.callLimit + 1) {
        throw new ReaderError("The model reached the lookup limit. Try a more specific question.");
      }
      return models.streamSimple(model, context, { ...options, maxRetries: 0 });
    },
  });
  agent.subscribe(event => {
    if (event.type === "message_start" && event.message.role === "assistant") emit({ type: "start" });
    if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") {
      emit({ type: "delta", text: event.assistantMessageEvent.delta });
    }
  });
  await agent.prompt({ role: "user", timestamp: Date.now(), content });
  const last = agent.state.messages.at(-1);
  if (last?.role !== "assistant" || last.stopReason !== "stop") {
    // Provider error bodies can echo request data, including credentials.
    throw new ReaderError("The provider could not finish the reply. Check your API key, model access, and usage limits.");
  }
  const text = last.content.filter(block => block.type === "text").map(block => block.text).join("");
  if (!text.trim()) throw new ReaderError("The provider returned an empty reply.");
  emit({ type: "done", text });
}

if (import.meta.main) {
  if (process.argv[2] === "--models") {
    console.log(JSON.stringify(models.getModels().map(({ provider, id, name, input }) =>
      ({ provider, id, name, vision: input.includes("image") }))));
  } else {
    const reader = createInterface({ input: process.stdin, terminal: false });
    const lines = reader[Symbol.asyncIterator]();
    const emit = event => process.stdout.write(JSON.stringify(event) + "\n");
    const next = async () => {
      const line = await lines.next();
      if (line.done) throw new Error("Input closed");
      return JSON.parse(line.value);
    };
    try {
      await answer(await next(), async (name, args) => {
        emit({ type: "tool", name, args });
        return await next();
      }, emit);
    } catch (error) {
      emit({ type: "error", text: error instanceof ReaderError ? error.message : "Could not complete the API request." });
    } finally {
      reader.close();
      process.stdin.destroy();
    }
  }
}
