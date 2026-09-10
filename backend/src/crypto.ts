const te = new TextEncoder();
const td = new TextDecoder();

export function b64url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export function b64urlDecode(input: string): Uint8Array {
  const padded = input.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - input.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

export function randomToken(bytes = 32): string {
  const data = new Uint8Array(bytes);
  crypto.getRandomValues(data);
  return b64url(data);
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', te.encode(value));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function hmac(keyText: string, data: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw', te.encode(keyText), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, te.encode(data)));
}

async function aesKey(secret: string): Promise<CryptoKey> {
  const digest = await crypto.subtle.digest('SHA-256', te.encode(secret));
  return crypto.subtle.importKey('raw', digest, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}

export async function encryptSecret(secret: string, plaintext: string): Promise<{ ciphertext: string; iv: string }> {
  const iv = new Uint8Array(12);
  crypto.getRandomValues(iv);
  const key = await aesKey(secret);
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, te.encode(plaintext));
  return { ciphertext: b64url(new Uint8Array(encrypted)), iv: b64url(iv) };
}

export async function decryptSecret(secret: string, ciphertext: string, iv: string): Promise<string> {
  const key = await aesKey(secret);
  const clear = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: b64urlDecode(iv) },
    key,
    b64urlDecode(ciphertext),
  );
  return td.decode(clear);
}

export async function signTicket(key: string, payload: Record<string, unknown>): Promise<string> {
  const header = b64url(te.encode(JSON.stringify({ alg: 'HS256', typ: 'SAT' })));
  const body = b64url(te.encode(JSON.stringify(payload)));
  const sig = b64url(await hmac(key, `${header}.${body}`));
  return `${header}.${body}.${sig}`;
}

export async function verifyTicket(key: string, token: string): Promise<Record<string, any> | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [header, body, sig] = parts;
  const expected = await hmac(key, `${header}.${body}`);
  const actual = b64urlDecode(sig);
  if (expected.length !== actual.length) return null;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected[i] ^ actual[i];
  if (diff !== 0) return null;
  try {
    const payload = JSON.parse(td.decode(b64urlDecode(body)));
    if (!payload.exp || Date.now() / 1000 > Number(payload.exp)) return null;
    return payload;
  } catch {
    return null;
  }
}
