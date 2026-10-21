import { encodeBytes } from "./session.js";

export function protectionSalt(enabled: boolean, password: string): string {
  return enabled && password
    ? encodeBytes(crypto.getRandomValues(new Uint8Array(16)))
    : "";
}
