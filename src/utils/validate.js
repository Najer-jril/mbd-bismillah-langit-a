import { badRequest } from "./httpError.js";

export const parseId = (value, name = "id") => {
  if (typeof value !== "string" || !/^\d{1,10}$/.test(value) || Number(value) > 2147483647 || Number(value) < 1) {
    throw badRequest(`Parameter ${name} harus berupa angka positif`);
  }
  return Number(value);
};

// Express 5: req.body = undefined bila request tanpa body. Selalu pakai body(req).
export const body = (req) => (req.body && typeof req.body === "object" && !Array.isArray(req.body) ? req.body : {});

export const requireString = (obj, key) => {
  if (typeof obj[key] !== "string") throw badRequest(`Field ${key} wajib berupa string`);
  return obj[key];
};
export const requireInt = (obj, key) => {
  if (!Number.isInteger(obj[key])) throw badRequest(`Field ${key} wajib berupa bilangan bulat`);
  return obj[key];
};
export const requireIntArray = (obj, key) => {
  if (!Array.isArray(obj[key]) || !obj[key].every(Number.isInteger)) throw badRequest(`Field ${key} wajib berupa array bilangan bulat`);
  return obj[key];
};
export const optionalStringArray = (obj, key) => {
  if (obj[key] === undefined) return null;
  if (!Array.isArray(obj[key]) || !obj[key].every((x) => typeof x === "string")) throw badRequest(`Field ${key} wajib berupa array string`);
  return obj[key];
};

// Query string bisa berupa array (?a=1&a=2) -> tolak.
export const queryString = (query, key) => {
  const v = query[key];
  if (v === undefined || v === "") return undefined;
  if (typeof v !== "string") throw badRequest(`Query ${key} tidak valid`);
  return v;
};
export const queryEnum = (query, key, allowed) => {
  const v = queryString(query, key);
  if (v !== undefined && !allowed.includes(v)) throw badRequest(`Query ${key} harus salah satu dari: ${allowed.join(", ")}`);
  return v;
};
export const queryFlag = (query, key) => queryString(query, key) === "1";
export const queryId = (query, key) => {
  const v = queryString(query, key);
  return v === undefined ? undefined : parseId(v, key);
};
export const likeParam = (s) => `%${s.replace(/[\\%_]/g, "\\$&")}%`; // escape wildcard LIKE
