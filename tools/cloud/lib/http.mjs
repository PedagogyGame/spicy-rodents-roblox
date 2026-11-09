// Thin fetch wrapper for apis.roblox.com. Authentication is NOT handled here on purpose: the
// container's egress proxy injects the owner's x-api-key for apis.roblox.com. This code never
// sets that header and never reads a key from anywhere.
//
// Proxy: Node's built-in fetch honours HTTPS_PROXY only with NODE_USE_ENV_PROXY=1 (Node >= 22.21);
// cloud.mjs re-executes itself with that variable set. TLS trusts NODE_EXTRA_CA_CERTS.
import { takeToken } from "./lock.mjs";

export class HttpError extends Error {
	constructor(method, url, status, body) {
		super(`${method} ${url} -> HTTP ${status}${body ? `: ${body.slice(0, 600)}` : ""}`);
		this.status = status;
		this.body = body;
	}
}

function explain(status, body) {
	if (status === 401) {
		return " (401: no valid API key reached Roblox. Inside the cloud container the proxy injects it; " +
			"outside it there is no key, by design. Check `curl -sS $HTTPS_PROXY/__agentproxy/status`.)";
	}
	if (status === 403 && /scope|permission/i.test(body || "")) {
		return " (403: the key lacks the scope for this endpoint; see PROJECT_IDS.md for the granted scopes)";
	}
	if (status === 403 || status === 407) {
		return " (403/407 can also be the egress proxy refusing the host; do not retry, report it)";
	}
	return "";
}

export async function request(method, url, { headers = {}, body, bucket = "reads", retries = 4, timeoutMs = 120_000 } = {}) {
	if (bucket) await takeToken(bucket);
	let attempt = 0;
	for (;;) {
		attempt += 1;
		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), timeoutMs);
		let res;
		try {
			res = await fetch(url, { method, headers, body, signal: controller.signal, redirect: "follow" });
		} catch (err) {
			clearTimeout(timer);
			if (attempt <= retries) {
				const backoff = 500 * 2 ** (attempt - 1);
				process.stderr.write(`[http] ${method} ${url} failed (${err.cause?.code || err.message}); retry ${attempt}/${retries} in ${backoff} ms\n`);
				await new Promise((r) => setTimeout(r, backoff));
				continue;
			}
			throw err;
		}
		clearTimeout(timer);
		const text = await res.text();
		if (res.ok) {
			return { status: res.status, headers: res.headers, text, json: safeJson(text) };
		}
		const retryable = res.status === 429 || res.status >= 500;
		if (retryable && attempt <= retries) {
			const retryAfter = Number(res.headers.get("retry-after"));
			const backoff = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 1000 * 2 ** (attempt - 1);
			process.stderr.write(`[http] ${method} ${url} -> ${res.status}; retry ${attempt}/${retries} in ${backoff} ms\n`);
			await new Promise((r) => setTimeout(r, backoff));
			continue;
		}
		const err = new HttpError(method, url, res.status, text);
		err.message += explain(res.status, text);
		throw err;
	}
}

export function safeJson(text) {
	try {
		return JSON.parse(text);
	} catch {
		return undefined;
	}
}

export async function getJson(url, opts = {}) {
	const r = await request("GET", url, { ...opts, bucket: opts.bucket ?? "reads" });
	if (r.json === undefined) throw new Error(`GET ${url}: response is not JSON: ${r.text.slice(0, 300)}`);
	return r.json;
}

export async function postJson(url, payload, opts = {}) {
	const r = await request("POST", url, {
		...opts,
		headers: { "content-type": "application/json", ...(opts.headers || {}) },
		body: JSON.stringify(payload),
	});
	if (r.json === undefined) throw new Error(`POST ${url}: response is not JSON: ${r.text.slice(0, 300)}`);
	return r.json;
}

// multipart/form-data with a JSON `request` part and a binary `fileContent` part (Assets API).
export function multipart(requestJson, fileBytes, contentType, filename) {
	const fd = new FormData();
	fd.append("request", JSON.stringify(requestJson));
	fd.append("fileContent", new Blob([fileBytes], { type: contentType }), filename);
	return fd;
}
