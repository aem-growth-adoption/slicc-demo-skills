#!/usr/bin/env node

/**
 * pipeline.js — liftoff-demo pipeline sprinkle helper.
 *
 * One command updates the persisted state file, re-renders the `.shtml`
 * from the template, and issues the `sprinkle send` — capturing
 * startedAt/completedAt timestamps automatically — so the skill's
 * "rewrite the .shtml after every send" rule cannot be forgotten and the
 * live duration timers never silently break.
 *
 * Usage:
 *   node pipeline.js init <slug> <url>
 *   node pipeline.js send <slug> <step> <status> [summary] [link]
 *
 * Runtime: plain Node, built-ins only. Runs in the cone's shell, where the
 * `sprinkle` CLI is on PATH.
 *
 * Env overrides (testing): PIPELINE_TEMPLATE, PIPELINE_SPRINKLE_DIR.
 * Set PIPELINE_DRY_RUN=1 to skip the real `sprinkle send` (prints instead).
 *
 * The step ids/order below MUST stay in sync with the template's baked
 * STEPS array (liftoff-demo/templates/pipeline.shtml.tpl).
 */

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const STEPS = [
	{ id: "setup", summary: "Cloning repo & preparing environment..." },
	{ id: "extraction", summary: "Capture page structure & brand" },
	{ id: "decomposition", summary: "Identify blocks & sections" },
	{ id: "blocks", summary: "Generate EDS blocks in parallel" },
	{ id: "assembly", summary: "Assemble page & create preview" },
	{ id: "deploy", summary: "Publish content & go live" },
];
const STATUSES = new Set(["pending", "active", "done"]);

const TEMPLATE =
	process.env.PIPELINE_TEMPLATE ||
	path.join(__dirname, "..", "templates", "pipeline.shtml.tpl");
const SPRINKLE_DIR = process.env.PIPELINE_SPRINKLE_DIR || "/shared/sprinkles";
const SPRINKLE_BIN = process.env.PIPELINE_SPRINKLE_BIN || "sprinkle";

function fail(msg) {
	process.stderr.write(`pipeline.js: ${msg}\n`);
	process.exit(1);
}

function sprinkleName(slug) {
	return `${slug}-pipeline`;
}

function sprinkleDir(slug) {
	return path.join(SPRINKLE_DIR, sprinkleName(slug));
}

function statePath(slug) {
	return path.join(sprinkleDir(slug), ".state.json");
}

function shtmlPath(slug) {
	return path.join(sprinkleDir(slug), `${sprinkleName(slug)}.shtml`);
}

function lastSendPath(slug) {
	return path.join(sprinkleDir(slug), ".last-send.json");
}

function readState(slug) {
	try {
		return JSON.parse(fs.readFileSync(statePath(slug), "utf8"));
	} catch {
		return fail(
			`no state for "${slug}" (${statePath(slug)}) — run "init" first.`,
		);
	}
}

function writeState(state) {
	fs.mkdirSync(sprinkleDir(state.slug), { recursive: true });
	fs.writeFileSync(statePath(state.slug), JSON.stringify(state, null, 2));
}

function render(state) {
	let tpl;
	try {
		tpl = fs.readFileSync(TEMPLATE, "utf8");
	} catch (e) {
		return fail(`cannot read template ${TEMPLATE}: ${e.message}`);
	}
	const island = JSON.stringify({ steps: state.steps });
	return tpl
		.split("{{URL}}")
		.join(state.url)
		.split("{{SLUG}}")
		.join(state.slug)
		.split("{{INITIAL_STATE_JSON}}")
		.join(island);
}

function writeShtml(state) {
	const out = shtmlPath(state.slug);
	fs.mkdirSync(path.dirname(out), { recursive: true });
	fs.writeFileSync(out, render(state));
	return out;
}

function publicState(state) {
	return { slug: state.slug, url: state.url, steps: state.steps };
}

function webhookBaseFor(state) {
	return state.webhookBase || process.env.LIFTOFF_WEBHOOK_BASE || "";
}

async function postProgress(state, reason) {
	const base = webhookBaseFor(state).replace(/\/+$/, "");
	if (!base) return;
	const body = JSON.stringify({
		type: "liftoff.pipeline.state",
		at: Date.now(),
		state: publicState(state),
	});
	try {
		const controller = new AbortController();
		const timeout = setTimeout(() => controller.abort(), 10_000);
		const res = await fetch(`${base}/events`, {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"x-slicc-hmac-sign":
					"OF1_LABS_HMAC:x-job-signature:x-job-timestamp",
			},
			body,
			signal: controller.signal,
		});
		clearTimeout(timeout);
		if (!res.ok) {
			const text = await res.text().catch(() => "");
			process.stderr.write(
				`pipeline.js: webhook post failed (${reason}): HTTP ${res.status} ${text.slice(0, 200)}\n`,
			);
			return;
		}
		process.stdout.write(`webhook progress posted (${reason})\n`);
	} catch (e) {
		process.stderr.write(
			`pipeline.js: webhook post failed (${reason}): ${e.message}\n`,
		);
	}
}

async function cmdInit(slug, url, webhookBase) {
	if (!slug || !url) fail("usage: init <slug> <url> [webhookBase]");
	const ts = Date.now();
	const steps = STEPS.map((s, i) => ({
		id: s.id,
		status: i === 0 ? "active" : "pending",
		summary: s.summary,
		link: null,
		startedAt: i === 0 ? ts : null,
		completedAt: null,
	}));
	const wb = webhookBase || process.env.LIFTOFF_WEBHOOK_BASE || "";
	const state = { slug, url, steps, webhookBase: wb };
	writeState(state);
	const out = writeShtml(state);
	process.stdout.write(`initialized ${sprinkleName(slug)}: ${out}\n`);
	await postProgress(state, "init");
}

function applyStatus(step, status, ts) {
	if (status === "active" && !step.startedAt) step.startedAt = ts;
	if (status === "done") {
		if (!step.completedAt) step.completedAt = ts;
		if (!step.startedAt) step.startedAt = step.completedAt;
	}
	step.status = status;
}

async function cmdSend(slug, stepId, status, summary, link) {
	if (!slug || !stepId || !status) {
		fail("usage: send <slug> <step> <status> [summary] [link]");
	}
	if (!STATUSES.has(status)) {
		fail(`invalid status "${status}" (expected: ${[...STATUSES].join(", ")})`);
	}
	const state = readState(slug);
	const step = state.steps.find((s) => s.id === stepId);
	if (!step) {
		fail(
			`unknown step "${stepId}" (valid: ${state.steps.map((s) => s.id).join(", ")})`,
		);
	}
	applyStatus(step, status, Date.now());
	if (summary) step.summary = summary;
	if (link) step.link = link;

	const payload = {
		step: step.id,
		status: step.status,
		summary: step.summary,
		link: step.link,
		startedAt: step.startedAt,
		completedAt: step.completedAt,
	};
	writeState(state);
	const out = writeShtml(state);
	// Record the exact payload so psend.sh (or a manual send) can push it even
	// when this process cannot spawn `sprinkle` itself (e.g. the SLICC realm).
	fs.writeFileSync(lastSendPath(slug), JSON.stringify(payload));
	issueSend(slug, payload);
	process.stdout.write(`sent ${stepId}=${status}; rewrote ${out}\n`);
	await postProgress(state, `send:${stepId}:${status}`);
}

function shSingleQuote(s) {
	return `'${s.replace(/'/g, "'\\''")}'`;
}

function printManualSend(name, json, reason) {
	// State + .shtml + .last-send.json are already written by the caller. The
	// live push is all that's left — emit a copy-runnable line (and psend.sh
	// reads .last-send.json to run it for you).
	process.stdout.write(
		`state + .shtml updated (${reason}). Push the live update yourself ` +
			`(or via psend.sh):\n${SPRINKLE_BIN} send ${name} ${shSingleQuote(json)}\n`,
	);
}

function issueSend(slug, payload) {
	const name = sprinkleName(slug);
	const json = JSON.stringify(payload);
	if (process.env.PIPELINE_DRY_RUN === "1") {
		printManualSend(name, json, "dry-run");
		return;
	}
	let r;
	try {
		r = spawnSync(SPRINKLE_BIN, ["send", name, json], {
			stdio: ["ignore", "inherit", "inherit"],
		});
	} catch (e) {
		// spawnSync is unavailable in this runtime (e.g. the SLICC browser realm,
		// where child_process cannot spawn). Degrade gracefully rather than crash.
		printManualSend(name, json, `spawnSync unavailable: ${e.message}`);
		return;
	}
	if (r.error && r.error.code === "ENOENT") {
		printManualSend(name, json, `"${SPRINKLE_BIN}" not found on PATH`);
		return;
	}
	if (r.error) fail(`sprinkle send failed: ${r.error.message}`);
	if (r.status !== 0) fail(`sprinkle send exited ${r.status}`);
}

async function cmdHeartbeat(slug) {
	if (!slug) fail("usage: heartbeat <slug>");
	const state = readState(slug);
	const deploy = state.steps.find((s) => s.id === "deploy");
	if (deploy?.status === "done") {
		process.stdout.write(
			`heartbeat skipped for ${slug}: terminal deploy done\n`,
		);
		return;
	}
	await postProgress(state, "heartbeat");
	process.stdout.write(`heartbeat posted for ${slug}\n`);
}

async function main() {
	const [cmd, ...rest] = process.argv.slice(2);
	if (cmd === "init") return cmdInit(rest[0], rest[1], rest[2]);
	if (cmd === "send")
		return cmdSend(rest[0], rest[1], rest[2], rest[3], rest[4]);
	if (cmd === "heartbeat") return cmdHeartbeat(rest[0]);
	return fail("usage: pipeline.js <init|send|heartbeat> ...");
}

main().catch((e) => fail(e.message));
