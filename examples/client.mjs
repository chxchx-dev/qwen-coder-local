import OpenAI from "openai";

const baseURL = process.env.QWEN_BASE_URL?.replace(/\/$/, "");
const apiKey = process.env.QWEN_API_KEY;
const model = process.env.QWEN_MODEL || "qwen2.5-coder-14b";

if (!baseURL || !apiKey) {
  throw new Error("Define QWEN_BASE_URL y QWEN_API_KEY antes de ejecutar el cliente.");
}

const client = new OpenAI({ baseURL, apiKey });
const response = await client.chat.completions.create({
  model,
  messages: [
    { role: "system", content: "You are an expert software engineering assistant." },
    { role: "user", content: "Create a TypeScript function that validates an email address." },
  ],
  temperature: 0.2,
  max_tokens: 1024,
});

console.log(response.choices[0]?.message?.content || "");
