/**
 * Tests for pipeline.js — exercises the real CLI entry point as a
 * subprocess (PIPELINE_DRY_RUN=1 so no real `sprinkle` is needed), against
 * a copy of the real template in a temp dir.
 *
 * Run: node --test liftoff-demo/scripts/
 */

const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const SCRIPT = path.join(__dirname, "pipeline.js");
const REAL_TEMPLATE = path.join(
	__dirname,
	"..",
	"templates",
	"pipeline.shtml.tpl",
);

let tmp;
let templatePath;
let sprinkleDir;

before(() => {
	tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pipeline-test-"));
	templatePath = path.join(tmp, "pipeline.shtml.tpl");
	fs.copyFileSync(REAL_TEMPLATE, templatePath);
	sprinkleDir = path.join(tmp, "sprinkles");
});

after(() => {
	fs.rmSync(tmp, { recursive: true, force: true });
});

function run(args) {
	return spawnSync(process.execPath, [SCRIPT, ...args], {
		encoding: "utf8",
		env: {
			...process.env,
			PIPELINE_TEMPLATE: templatePath,
			PIPELINE_SPRINKLE_DIR: sprinkleDir,
			PIPELINE_DRY_RUN: "1",
		},
	});
}

function stateOf(slug) {
	const p = path.join(sprinkleDir, `${slug}-pipeline`, ".state.json");
	return JSON.parse(fs.readFileSync(p, "utf8"));
}

function shtmlOf(slug) {
	const p = path.join(
		sprinkleDir,
		`${slug}-pipeline`,
		`${slug}-pipeline.shtml`,
	);
	return fs.readFileSync(p, "utf8");
}

test("init creates state + shtml with setup active and no leftover placeholders", () => {
	const r = run(["init", "demo", "https://example.com/basecamp"]);
	assert.equal(r.status, 0, r.stderr);

	const state = stateOf("demo");
	assert.equal(state.slug, "demo");
	assert.equal(state.url, "https://example.com/basecamp");
	assert.equal(state.steps.length, 6);
	assert.equal(state.steps[0].id, "setup");
	assert.equal(state.steps[0].status, "active");
	assert.equal(typeof state.steps[0].startedAt, "number");
	assert.equal(state.steps[1].status, "pending");
	assert.equal(state.steps[1].startedAt, null);

	const html = shtmlOf("demo");
	assert.ok(!html.includes("{{"), "no unreplaced placeholders remain");
	assert.ok(html.includes("https://example.com/basecamp"), "url substituted");
	assert.ok(
		html.includes('"id":"setup","status":"active"'),
		"island reflects state",
	);
});

test("send done captures completedAt, preserves startedAt, updates summary", () => {
	run(["init", "demo2", "https://example.com/"]);
	const started = stateOf("demo2").steps[0].startedAt;

	const r = run(["send", "demo2", "setup", "done", "Environment ready"]);
	assert.equal(r.status, 0, r.stderr);
	assert.ok(
		r.stdout.includes("sprinkle send demo2-pipeline"),
		"dry-run emits a runnable sprinkle send line",
	);

	const setup = stateOf("demo2").steps[0];
	assert.equal(setup.status, "done");
	assert.equal(setup.startedAt, started, "startedAt preserved from init");
	assert.equal(typeof setup.completedAt, "number");
	assert.equal(setup.summary, "Environment ready");
});

test("send active on a pending step sets startedAt and re-renders shtml", () => {
	run(["init", "demo3", "https://example.com/"]);
	const r = run([
		"send",
		"demo3",
		"extraction",
		"active",
		"Navigating to page...",
	]);
	assert.equal(r.status, 0, r.stderr);

	const extraction = stateOf("demo3").steps[1];
	assert.equal(extraction.status, "active");
	assert.equal(typeof extraction.startedAt, "number");
	assert.equal(extraction.completedAt, null);

	assert.ok(
		shtmlOf("demo3").includes("Navigating to page..."),
		"summary rendered into shtml",
	);
});

test("send accepts an optional link (e.g. deploy done)", () => {
	run(["init", "demo4", "https://example.com/"]);
	const url = "https://main--repo--owner.aem.page/";
	const r = run(["send", "demo4", "deploy", "done", "Live!", url]);
	assert.equal(r.status, 0, r.stderr);

	const deploy = stateOf("demo4").steps.find((s) => s.id === "deploy");
	assert.equal(deploy.link, url);
	assert.ok(r.stdout.includes(url), "link present in sent payload");
});

test("invalid status exits non-zero with a helpful message", () => {
	run(["init", "demo5", "https://example.com/"]);
	const r = run(["send", "demo5", "setup", "finished"]);
	assert.notEqual(r.status, 0);
	assert.ok(r.stderr.includes("invalid status"), r.stderr);
});

test("unknown step exits non-zero and lists valid ids", () => {
	run(["init", "demo6", "https://example.com/"]);
	const r = run(["send", "demo6", "bogus", "active"]);
	assert.notEqual(r.status, 0);
	assert.ok(r.stderr.includes("unknown step"), r.stderr);
	assert.ok(r.stderr.includes("setup"), "lists valid step ids");
});

test("send before init exits non-zero telling you to init first", () => {
	const r = run(["send", "never-inited", "setup", "active"]);
	assert.notEqual(r.status, 0);
	assert.ok(r.stderr.includes('run "init" first'), r.stderr);
});

test("send degrades gracefully when the sprinkle binary is not on PATH", () => {
	run(["init", "demo8", "https://example.com/"]);
	const r = spawnSync(
		process.execPath,
		[SCRIPT, "send", "demo8", "setup", "done", "ok"],
		{
			encoding: "utf8",
			env: {
				...process.env,
				PIPELINE_TEMPLATE: templatePath,
				PIPELINE_SPRINKLE_DIR: sprinkleDir,
				PIPELINE_DRY_RUN: "",
				PIPELINE_SPRINKLE_BIN: "definitely-not-a-real-binary-xyz",
			},
		},
	);
	assert.equal(r.status, 0, r.stderr);
	assert.ok(r.stdout.includes("Push the live update yourself"), r.stdout);
	// State + .shtml must still have been written before the send was attempted.
	assert.equal(stateOf("demo8").steps[0].status, "done");
});

test("send records the exact payload to .last-send.json", () => {
	run(["init", "demo9", "https://example.com/"]);
	run(["send", "demo9", "deploy", "done", "Live!", "https://x.aem.page/"]);
	const p = path.join(sprinkleDir, "demo9-pipeline", ".last-send.json");
	const payload = JSON.parse(fs.readFileSync(p, "utf8"));
	assert.equal(payload.step, "deploy");
	assert.equal(payload.status, "done");
	assert.equal(payload.link, "https://x.aem.page/");
	assert.equal(typeof payload.completedAt, "number");
});

test("psend.sh bridges pipeline.js state work to a real sprinkle send", () => {
	const bin = fs.mkdtempSync(path.join(os.tmpdir(), "pipeline-bin-"));
	const log = path.join(bin, "sprinkle.log");
	const shim = path.join(bin, "sprinkle");
	fs.writeFileSync(shim, `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> "${log}"\n`);
	fs.chmodSync(shim, 0o755);

	const env = {
		...process.env,
		PATH: `${bin}:${process.env.PATH}`,
		PIPELINE_TEMPLATE: templatePath,
		PIPELINE_SPRINKLE_DIR: sprinkleDir,
	};
	const init = spawnSync(process.execPath, [SCRIPT, "init", "demo10", "https://example.com/"], {
		encoding: "utf8",
		env: { ...env, PIPELINE_DRY_RUN: "1" },
	});
	assert.equal(init.status, 0, init.stderr);

	const psend = path.join(__dirname, "psend.sh");
	const r = spawnSync("bash", [psend, "demo10", "setup", "done", "ok"], {
		encoding: "utf8",
		env,
	});
	assert.equal(r.status, 0, r.stderr);

	const sent = fs.readFileSync(log, "utf8");
	assert.ok(sent.includes("send demo10-pipeline"), sent);
	assert.ok(sent.includes('"status":"done"'), sent);
	assert.ok(sent.includes('"step":"setup"'), sent);
	fs.rmSync(bin, { recursive: true, force: true });
});

test("re-rendered shtml stays valid JSON in the data island", () => {
	run(["init", "demo7", "https://example.com/"]);
	run(["send", "demo7", "setup", "done", "ok"]);
	const html = shtmlOf("demo7");
	const m = html.match(
		/<script id="initial-state" type="application\/json">\s*([\s\S]*?)<\/script>/,
	);
	assert.ok(m, "initial-state island present");
	const parsed = JSON.parse(m[1]);
	assert.equal(parsed.steps.length, 6);
	assert.equal(parsed.steps[0].status, "done");
});
