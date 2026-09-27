/**
 * The anonymous key that finds the user's stored numbers in Tiger Data. 32 random bytes from
 * the browser's CSPRNG, base64url (43 characters, the format the backend accepts). The server
 * only stores its SHA-256. Kept in this browser; copying it to another browser restores access.
 */
const STORAGE_KEY = "arm:profileKey";

export function newProfileKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function peekProfileKey(): string | null {
  try {
    return localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

export function ensureProfileKey(): string {
  const existing = peekProfileKey();
  if (existing) return existing;
  const key = newProfileKey();
  try {
    localStorage.setItem(STORAGE_KEY, key);
  } catch {
    // Private mode: the key lives for this session only.
  }
  return key;
}
