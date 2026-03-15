import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildProgram } from "../../src/cli.ts";
import { runHelpCommand } from "../../src/commands/help.ts";
import { runVersionCommand } from "../../src/commands/version.ts";

// ---------------------------------------------------------------
// Command registration
// ---------------------------------------------------------------

describe("CLI root contracts - command registration", () => {
  it("registers all 9 public commands", () => {
    const program = buildProgram();
    const names = program.commands.map((c) => c.name());

    const expected = [
      "deploy",
      "resume",
      "list",
      "status",
      "logs",
      "doctor",
      "destroy",
      "help",
      "version",
    ];
    for (const name of expected) {
      assert.ok(names.includes(name), `Missing command: ${name}`);
    }
  });
});

// ---------------------------------------------------------------
// Help output
// ---------------------------------------------------------------

describe("CLI root contracts - help output", () => {
  it("help command output contains all command labels", () => {
    const lines: string[] = [];
    const out = { write: (s: string) => { lines.push(s); } };
    runHelpCommand(out);
    const output = lines.join("");

    const expectedCommands = [
      "deploy",
      "resume",
      "list",
      "status",
      "logs",
      "doctor",
      "destroy",
      "help",
      "version",
    ];
    for (const name of expectedCommands) {
      assert.ok(output.includes(name), `Help output missing command: ${name}`);
    }
  });

  it("help command output contains usage header", () => {
    const lines: string[] = [];
    const out = { write: (s: string) => { lines.push(s); } };
    runHelpCommand(out);
    const output = lines.join("");
    assert.ok(output.includes("hermes-fly"), "Help missing 'hermes-fly'");
    assert.ok(output.includes("Commands:"), "Help missing 'Commands:' section");
  });
});

// ---------------------------------------------------------------
// Version output
// ---------------------------------------------------------------

describe("CLI root contracts - version contracts", () => {
  it("version subcommand outputs hermes-fly version string", () => {
    const lines: string[] = [];
    const out = { write: (s: string) => { lines.push(s); } };
    runVersionCommand(out);
    const output = lines.join("");
    assert.ok(output.startsWith("hermes-fly "), `Version output should start with 'hermes-fly ': got '${output}'`);
    assert.match(output, /hermes-fly \d+\.\d+\.\d+/);
  });
});

// ---------------------------------------------------------------
// Stubs: deploy, resume, doctor, destroy
// ---------------------------------------------------------------

describe("CLI root contracts - stub commands sentinel", () => {
  it("deploy stub is registered", () => {
    const program = buildProgram();
    const cmd = program.commands.find((c) => c.name() === "deploy");
    assert.ok(cmd !== undefined, "deploy command not registered");
  });

  it("resume stub is registered", () => {
    const program = buildProgram();
    const cmd = program.commands.find((c) => c.name() === "resume");
    assert.ok(cmd !== undefined, "resume command not registered");
  });

  it("doctor stub is registered", () => {
    const program = buildProgram();
    const cmd = program.commands.find((c) => c.name() === "doctor");
    assert.ok(cmd !== undefined, "doctor command not registered");
  });

  it("destroy stub is registered", () => {
    const program = buildProgram();
    const cmd = program.commands.find((c) => c.name() === "destroy");
    assert.ok(cmd !== undefined, "destroy command not registered");
  });
});
