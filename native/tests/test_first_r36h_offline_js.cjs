#!/usr/bin/env node
// Host-side DOM stub verifies the offline JavaScript contract only.
// Actual WebKit rendering and R36H GPIO/display require the physical console.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "../../installer/www/primeiro-teste.html"), "utf8");
const match = html.match(/<script>([\s\S]*?)<\/script>/i);
assert(match, "Expected exactly one inline offline diagnostic script");
assert.equal((html.match(/<script\b/gi) || []).length, 1);

function run(simulateError) {
  const elements = new Map();
  const callbacks = new Map();
  for (const id of ["js-state", "details", "test-button", "click-count"]) {
    elements.set(id, {
      textContent: "",
      className: "",
      addEventListener(eventName, callback) { callbacks.set(id + ":" + eventName, callback); },
    });
  }
  const document = {
    getElementById(id) {
      assert(elements.has(id), "Page script tried to access unexpected DOM ID " + id);
      return elements.get(id);
    },
    createElement(tag) {
      assert.equal(tag, "span");
      if (simulateError) {
        return {get textContent() { return "BROKEN_DOM"; }, set textContent(_value) {}};
      }
      return {textContent: ""};
    },
  };
  vm.runInNewContext(match[1], {document, Error, String}, {timeout: 3000});
  return {elements, callbacks};
}
const good = run(false);
assert.equal(good.elements.get("js-state").textContent, "JS OK");
assert.equal(good.elements.get("js-state").className, "state pass");
assert.match(good.elements.get("details").textContent, /Sem internet/);
const click = good.callbacks.get("test-button:click");
assert.equal(typeof click, "function");
click();
assert.equal(good.elements.get("click-count").textContent, "Cliques: 1");
click();
assert.equal(good.elements.get("click-count").textContent, "Cliques: 2");

const bad = run(true);
assert.equal(bad.elements.get("js-state").textContent, "JS FALHOU");
assert.equal(bad.elements.get("js-state").className, "state fail");
assert.match(bad.elements.get("details").textContent, /DOM textContent/);
console.log("FIRST_FRAME_OFFLINE_JS_DOM=PASS_HOST_SIMULATION_NOT_R36H");
