export function protectionSalt(enabled: boolean, password: string): Uint8Array {
  return enabled && password
    ? crypto.getRandomValues(new Uint8Array(16))
    : new Uint8Array(0);
}
