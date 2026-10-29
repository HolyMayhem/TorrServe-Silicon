// Standard PBKDF2 runs in the browser; the Worker receives a password-equivalent key,
// never the user's plaintext password. HTTPS remains mandatory.
export const iterations = 600000;
function decode(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{22}$/.test(value))
    throw new Error("Некорректные параметры входа.");
  return Uint8Array.from(
    atob(value.replace(/-/g, "+").replace(/_/g, "/") + "=="),
    (c) => c.charCodeAt(0),
  );
}
function encode(bytes) {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}
export function newSalt() {
  return encode(crypto.getRandomValues(new Uint8Array(16)));
}
export function validateNewPassword(password) {
  const normalized=password.normalize("NFC");
  const length = [...normalized].length;
  if (length < 12 || length > 128 || !normalized.trim())
    throw new Error(
      "Пароль должен содержать от 12 до 128 символов. Можно использовать длинную фразу.",
    );
}
export async function derivePassword(password, salt) {
  if (typeof password !== "string" || [...password].length > 128)
    throw new Error("Пароль слишком длинный.");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password.normalize("NFC")),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt: decode(salt), iterations },
    key,
    256,
  );
  return encode(new Uint8Array(bits));
}
export async function credentialForInput(value, configuration) {
  if (configuration?.mode === "key") {
    if (!/^[A-Za-z0-9_-]{43}$/.test(value))
      throw new Error("Введите текущий ключ администратора.");
    return value;
  }
  if (
    configuration?.mode !== "password" ||
    configuration.algorithm !== "PBKDF2-SHA256" ||
    configuration.iterations !== iterations
  )
    throw new Error("Параметры входа изменились. Обновите страницу.");
  return derivePassword(value, configuration.salt);
}
