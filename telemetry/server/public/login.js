import { credentialForInput } from "/admin/password-crypto.js";
const form = document.getElementById("login");
const input = document.getElementById("key");
const button = document.getElementById("submit");
const status = document.getElementById("status");
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  button.disabled = true;
  status.textContent = "";
  status.classList.remove("success");
  const value = input.value;
  input.value = "";
  try {
    const configurationResponse = await fetch("/admin/auth-config", {
      cache: "no-store",signal:AbortSignal.timeout(10000),
    });
    if (!configurationResponse.ok)
      throw new Error(
        "Не удалось получить параметры входа. Обновите страницу.",
      );
    const configuration = await configurationResponse.json();
    const key = await credentialForInput(value, configuration);
    const result = await fetch("/admin/login", {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key }),
      signal: AbortSignal.timeout(10000),
    });
    if (result.status === 204) {
      location.replace("/admin/");
      return;
    }
    status.textContent =
      result.status === 429
        ? "Слишком много попыток. Повторите через минуту."
        : result.status === 503
          ? "Вход ещё не настроен администратором."
          : "Неверный пароль или начальный ключ.";
  } catch (error) {
    status.textContent =
      error instanceof TypeError || error.name === "TimeoutError"
        ? "Не удалось подключиться. Повторите попытку."
        : error.message;
  } finally {
    button.disabled = false;
    input.focus();
  }
});

if (new URLSearchParams(location.search).get("changed") === "1") {
  status.classList.add("success");
  status.textContent = "Пароль изменён. Войдите с новым паролем.";
  history.replaceState(null, "", "/admin/login");
}
