import {
  credentialForInput,
  derivePassword,
  newSalt,
  validateNewPassword,
} from "/admin/password-crypto.js";
const $ = (id) => document.getElementById(id);
const number = new Intl.NumberFormat("ru-RU");
const countryNames =
  typeof Intl.DisplayNames === "function"
    ? new Intl.DisplayNames(["ru"], { type: "region" })
    : null;
const percent = new Intl.NumberFormat("ru-RU", {
  style: "percent",
  maximumFractionDigits: 1,
});
const shortDate = (value) =>
  new Intl.DateTimeFormat("ru-RU", {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
  }).format(new Date(value + "T00:00:00Z"));
const timestamp = (seconds) =>
  new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  }).format(new Date(seconds * 1000)) + " UTC";
const day = (date) => date.toISOString().slice(0, 10);
const today = new Date();
const earliest = day(new Date(today.getTime() - 89 * 86400000));
for (const id of ["start", "end"]) {
  $(id).max = day(today);
  $(id).min = earliest;
}
$("end").value = day(today);
let requestController;

function setPreset(days) {
  const end = new Date($("end").value + "T00:00:00Z");
  $("start").value = day(
    new Date(
      Math.max(
        new Date(earliest).getTime(),
        end.getTime() - (days - 1) * 86400000,
      ),
    ),
  );
  for (const button of document.querySelectorAll("[data-days]"))
    button.setAttribute(
      "aria-pressed",
      String(Number(button.dataset.days) === days),
    );
}
const ns = "http://www.w3.org/2000/svg";
function svgElement(tag, attributes = {}, text) {
  const element = document.createElementNS(ns, tag);
  for (const [key, value] of Object.entries(attributes))
    element.setAttribute(key, value);
  if (text !== undefined) element.textContent = text;
  return element;
}
function chart(rows) {
  const width = 1000,
    height = 250,
    left = 40,
    right = 12,
    top = 16,
    bottom = 32;
  const max = Math.max(
    4,
    Math.ceil(Math.max(0, ...rows.map((r) => r.active)) / 4) * 4,
  );
  const x = (i) =>
    left + (i / Math.max(1, rows.length - 1)) * (width - left - right);
  const y = (v) => height - bottom - (v / max) * (height - top - bottom);
  const svg = svgElement("svg", {
    viewBox: `0 0 ${width} ${height}`,
    role: "img",
    "aria-label": `Активные установки по дням. Верхняя граница шкалы ${number.format(max)}. Точные значения доступны в таблице ниже.`,
  });
  for (let i = 0; i <= 4; i++) {
    const value = Math.ceil((max / 4) * i);
    svg.append(
      svgElement("line", {
        x1: left,
        x2: width - right,
        y1: y(value),
        y2: y(value),
        class: "grid",
      }),
    );
    svg.append(
      svgElement(
        "text",
        { x: left - 12, y: y(value) + 4, "text-anchor": "end" },
        number.format(value),
      ),
    );
  }
  const path = rows
    .map((r, i) => `${i ? "L" : "M"} ${x(i)} ${y(r.active)}`)
    .join(" ");
  svg.append(
    svgElement("path", {
      d: `${path} L ${x(rows.length - 1)} ${y(0)} L ${x(0)} ${y(0)} Z`,
      class: "area",
    }),
  );
  svg.append(svgElement("path", { d: path, class: "line" }));
  const labels = [
    ...new Set([0, Math.floor((rows.length - 1) / 2), rows.length - 1]),
  ];
  for (const i of labels)
    svg.append(
      svgElement(
        "text",
        {
          x: x(i),
          y: height - 6,
          "text-anchor":
            i === 0 ? "start" : i === rows.length - 1 ? "end" : "middle",
        },
        shortDate(rows[i].day),
      ),
    );
  rows.forEach((r, i) => {
    const dot = svgElement("circle", {
      cx: x(i),
      cy: y(r.active),
      r: rows.length > 31 ? 2 : 3,
    });
    dot.append(
      svgElement(
        "title",
        {},
        `${r.day}: ${number.format(r.active)} активных, ${number.format(r.new_installations)} новых ID`,
      ),
    );
    svg.append(dot);
  });
  $("chart").replaceChildren(svg);
  $("daily-table").replaceChildren(
    ...rows.map((row) => {
      const tr = document.createElement("tr");
      for (const value of [
        row.day,
        number.format(row.active),
        number.format(row.new_installations),
      ]) {
        const td = document.createElement("td");
        td.textContent = value;
        tr.append(td);
      }
      return tr;
    }),
  );
}
function distribution(id, rows, total) {
  if (!total) {
    const p = document.createElement("p");
    p.className = "empty";
    p.textContent = "За этот период данных пока нет.";
    $(id).replaceChildren(p);
    return;
  }
  $(id).replaceChildren(
    ...rows.map((row) => {
      const item = document.createElement("div");
      item.className = "distribution-row";
      const labels = document.createElement("div");
      labels.className = "row-labels";
      const label = document.createElement("span");
      label.textContent =
        id === "countries"
          ? row.label === "ZZ"
            ? "Не определено"
            : (countryNames?.of(row.label) ?? row.label)
          : row.label;
      const count = document.createElement("span");
      count.className = "row-count";
      count.textContent = `${number.format(row.count)} · ${percent.format(row.count / total)}`;
      labels.append(label, count);
      const bar = svgElement("svg", {
        viewBox: "0 0 100 3",
        preserveAspectRatio: "none",
        "aria-hidden": "true",
      });
      bar.append(
        svgElement("rect", { width: 100, height: 3, class: "track" }),
        svgElement("rect", {
          width: (row.count / total) * 100,
          height: 3,
          class: "fill",
        }),
      );
      item.append(labels, bar);
      return item;
    }),
  );
}
async function load() {
  requestController?.abort();
  requestController = new AbortController();
  const controller = requestController;
  $("refresh").disabled = true;
  $("message").hidden = false;
  $("message").className = "message";
  $("message").textContent = "Загрузка данных…";
  try {
    if ($("start").value > $("end").value)
      throw new Error("Дата начала должна быть не позже даты окончания.");
    const params = new URLSearchParams({
      start: $("start").value,
      end: $("end").value,
    });
    const response = await fetch("/admin/api/stats?" + params, {
      credentials: "same-origin",
      cache: "no-store",
      signal: controller.signal,
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      if ([401, 403].includes(response.status))
        throw new Error(
          "Сессия администратора завершена. Откройте панель заново и войдите.",
        );
      if (response.status === 400)
        throw new Error(
          "Выберите корректный диапазон в пределах последних 90 дней UTC.",
        );
      throw new Error(
        "API недоступен. Проверьте D1 и настройки доступа, затем повторите запрос.",
      );
    }
    const data = await response.json();
    $("logout").hidden = data.system.authMode !== "key";
    $("change-password").hidden = data.system.authMode !== "key";
    for (const id of ["installations", "dau", "wau", "mau"])
      $(id).textContent = number.format(data.metrics[id]);
    $("range-caption").textContent =
      `${shortDate(data.range.start)} — ${shortDate(data.range.end)} · UTC`;
    chart(data.activity);
    for (const id of ["versions", "macOS", "processors", "countries"])
      distribution(id, data[id], data.adoption.active);
    $("latest-version").textContent = data.adoption.latestVersion
      ? `TorrServe Silicon ${data.adoption.latestVersion}`
      : "Версия релиза не задана администратором";
    $("adoption").textContent =
      data.adoption.fraction === null
        ? "—"
        : percent.format(data.adoption.fraction);
    $("adoption-count").textContent =
      `${number.format(data.adoption.current)} из ${number.format(data.adoption.active)} активных установок в периоде`;
    $("adoption-fill").setAttribute(
      "width",
      String((data.adoption.fraction ?? 0) * 100),
    );
    $("system-status").textContent =
      data.system.environment === "local"
        ? "API доступен · локальная D1"
        : "API и D1 доступны";
    $("system-dot").className = "system-dot ready";
    $("last-received").textContent = data.system.lastReceivedAt
      ? `Последний heartbeat: ${timestamp(data.system.lastReceivedAt)}`
      : "Первый heartbeat ещё не получен";
    $("last-refreshed").textContent =
      `Проверено: ${timestamp(Date.parse(data.generatedAt) / 1000)}`;
    $("content").hidden = false;
    $("message").hidden = true;
  } catch (error) {
    if (error.name === "AbortError") return;
    $("content").hidden = true;
    $("message").textContent =
      error instanceof SyntaxError
        ? "Требуется вход администратора. Откройте панель заново."
        : error.message;
    $("message").className = "message error";
    $("system-dot").className = "system-dot";
    $("system-status").textContent = "Не удалось обновить данные";
  } finally {
    if (requestController === controller) $("refresh").disabled = false;
  }
}
for (const button of document.querySelectorAll("[data-days]"))
  button.addEventListener("click", () => {
    setPreset(Number(button.dataset.days));
    load();
  });
for (const id of ["start", "end"])
  $(id).addEventListener("input", () => {
    for (const button of document.querySelectorAll("[data-days]"))
      button.setAttribute("aria-pressed", "false");
  });
$("filters").addEventListener("submit", (event) => {
  event.preventDefault();
  load();
});
$("refresh").addEventListener("click", load);
setPreset(30);
load();
$("logout").addEventListener("click", async () => {
  try {
    const result = await fetch("/admin/logout", {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
    });
    if (result.ok || result.status === 401) location.replace("/admin/login");
    else throw new Error("Не удалось завершить сессию. Повторите попытку.");
  } catch (error) {
    $("message").hidden = false;
    $("message").textContent = error.message;
    $("message").className = "message error";
  }
});
window.addEventListener("pagehide", () => {
  $("content").hidden = true;
});
window.addEventListener("pageshow", (event) => {
  if (event.persisted) load();
});

const passwordDialog = $("password-dialog");
const passwordForm = $("password-form");
$("change-password").addEventListener("click", () => {
  passwordForm.reset();
  $("password-status").textContent = "";
  passwordDialog.showModal();
});
$("password-cancel").addEventListener("click", () => passwordDialog.close());
passwordDialog.addEventListener("close", () => passwordForm.reset());
passwordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const button = $("password-save");
  button.disabled = true;
  $("password-cancel").disabled = true;
  $("password-status").textContent = "Сохраняем пароль…";
  for (const id of ["current-password", "new-password", "confirm-password"])
    $(id).disabled = true;
  try {
    const current = $("current-password").value;
    const next = $("new-password").value;
    validateNewPassword(next);
    if (next !== $("confirm-password").value)
      throw new Error("Новые пароли не совпадают.");
    if (next.normalize("NFC") === current.normalize("NFC"))
      throw new Error("Новый пароль должен отличаться от текущего.");
    const configResponse = await fetch("/admin/auth-config", {
      signal:AbortSignal.timeout(10000),
      cache: "no-store",
      credentials: "same-origin",
    });
    if (!configResponse.ok)
      throw new Error("Не удалось получить параметры входа.");
    const configuration = await configResponse.json();
    const currentKey = await credentialForInput(current, configuration);
    const salt = newSalt();
    const newKey = await derivePassword(next, salt);
    const result = await fetch("/admin/api/password", {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ currentKey, newKey, salt }),
      signal: AbortSignal.timeout(15000),
    });
    if (result.status === 204) {
      passwordForm.reset();
      $("content").hidden = true;
      location.replace("/admin/login?changed=1");
      return;
    }
    if (result.status === 401)
      throw new Error(
        "Текущий пароль неверен или сессия завершена. Войдите заново при необходимости.",
      );
    if (result.status === 409)
      throw new Error("Пароль уже изменён в другой сессии. Войдите заново.");
    if (result.status === 429)
      throw new Error("Слишком много попыток. Повторите через минуту.");
    throw new Error("Не удалось сохранить пароль. Повторите попытку.");
  } catch (error) {
    $("password-status").textContent = error.name==="TimeoutError" ? "Сервер не ответил вовремя. Повторите попытку." : error.message;
  } finally {
    button.disabled = false;
    $("password-cancel").disabled = false;
    for (const id of ["current-password", "new-password", "confirm-password"])
      $(id).disabled = false;
  }
});

passwordDialog.addEventListener("cancel", (event) => {
  if ($("password-save").disabled) event.preventDefault();
});
