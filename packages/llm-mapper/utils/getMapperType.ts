import { HeliconeRequest, MapperType, Provider } from "../types";

const isAssistantRequest = (request: HeliconeRequest) => {
  return (
    request.request_body.hasOwnProperty("assistant_id") ||
    request.request_body.hasOwnProperty("metadata") ||
    request.response_body.hasOwnProperty("metadata") ||
    (Array.isArray(request.response_body.data) &&
      request.response_body.data.some((item: any) =>
        item.hasOwnProperty("metadata")
      ))
  );
};

const isRealtimeRequest = (request: HeliconeRequest) => {
  return (
    request.response_body?.object === "realtime.session" ||
    request.response_body?.messages?.some(
      (msg: any) => msg.content?.type === "session.created"
    )
  );
};

export const getMapperTypeFromHeliconeRequest = (
  heliconeRequest: HeliconeRequest,
  model: string
) => {
  if (heliconeRequest.request_body?._type === "vector_db") {
    return "vector-db";
  }

  if (heliconeRequest.request_body?._type === "tool") {
    return "tool";
  }

  // Check for OpenAI Assistant responses
  if (
    heliconeRequest.response_body?.object === "thread.run" ||
    heliconeRequest.response_body?.assistant_id ||
    heliconeRequest.response_body?.thread_id
  ) {
    return "openai-assistant";
  }

  // Check for realtime responses
  if (isRealtimeRequest(heliconeRequest)) {
    return "openai-realtime";
  }

  return getMapperType({
    model,
    provider: heliconeRequest.provider,
    path: heliconeRequest.request_path,
    isAssistant: isAssistantRequest(heliconeRequest),
    targetUrl: heliconeRequest.target_url,
  });
};

export const getMapperType = ({
  model,
  provider,
  path,
  isAssistant,
  targetUrl,
}: {
  model: string;
  provider: Provider;
  path?: string | null;
  isAssistant?: boolean;
  targetUrl?: string | null;
}): MapperType => {
  if (
    targetUrl &&
    targetUrl.includes("chat/completions") &&
    provider === "GOOGLE"
  ) {
    return "openai-chat";
  }

  if (!model) {
    return "openai-chat";
  }

  if (typeof model !== "string") {
    return "openai-chat";
  }

  if (targetUrl?.includes("/v1/response") && provider === "OPENAI") {
    return "openai-response";
  }

  if (model.includes("deepseek")) {
    return "openai-chat";
  }

  if (model === "vector_db") {
    return "vector-db";
  }

  if (/^gpt-3\.5-turbo-instruct/.test(model)) {
    return "openai-instruct";
  }

  if (model == "black-forest-labs/FLUX.1-schnell") {
    return "black-forest-labs-image";
  }

  if (
    /^mistralai\/Mistral-7B-Instruct-v\d+\.\d+$/.test(model) ||
    /^(ft:)?gpt-(4|3\.5|35)(?!-turbo-instruct)(-turbo)?(-\d{2}k)?(-\d{4})?/.test(
      model
    ) ||
    /^o1-(preview|mini)(-\d{4}-\d{2}-\d{2})?$/.test(model) ||
    /^meta-llama\/.*/i.test(model) ||
    provider === "OPENROUTER" ||
    provider === "CUSTOM" ||
    provider === "GROQ" ||
    provider === "TOGETHER" ||
    (provider as any) === "TOGETHERAI" ||
    path?.includes("oai2ant") ||
    model == "gpt-4-vision-preview" ||
    model == "gpt-4-1106-vision-preview"
  ) {
    if (provider === "CUSTOM" && /^claude/.test(model)) {
      return "anthropic-chat";
    }
    return "openai-chat";
  }

  // Check for any Anthropic model regardless of provider
  if (
    /^claude/.test(model) ||
    model.includes("claude") ||
    model.includes("anthropic") ||
    provider === "ANTHROPIC" ||
    (provider === "AWS" &&
      (model.includes("claude") || model.includes("anthropic")))
  ) {
    return "anthropic-chat";
  }

  // Check for any Llama API model
  if (
    /^Llama/.test(model) ||
    model.includes("Llama") ||
    provider === "LLAMA"
  ) {
    return "llama-chat";
  }

  if (isAssistant) {
    return "openai-assistant";
  }

  if (
    model &&
    (model.toLowerCase().includes("gemini") || provider === "GOOGLE")
  ) {
    if (provider === "OPENAI") {
      return "openai-chat";
    }
    return "gemini-chat";
  }

  if (model === "dall-e-3" || model === "dall-e-2") {
    return "openai-image";
  }

  if (/^text-moderation(-\[\w+\]|-\d+)?$/.test(model)) {
    return "openai-moderation";
  }

  if (/^text-embedding/.test(model)) {
    return "openai-embedding";
  }

  return "openai-chat";
};
