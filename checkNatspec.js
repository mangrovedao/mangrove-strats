/* ********* Mangrove tooling script ********* *
This script verifies that select files have natspec comments for all parameters and return values of functions
*/

const fs = require("fs");
const path = require("path");
const cwd = process.cwd();

// recursively gather file paths in dir
let all_files = (dir, accumulator = []) => {
  for (const file_name of fs.readdirSync(dir)) {
    const file_path = path.join(dir, file_name);
    if (fs.statSync(file_path).isDirectory()) {
      all_files(file_path, accumulator);
    } else {
      if (file_name.endsWith(".json")) {
        accumulator.push(file_path);
      }
    }
  }
  return accumulator;
};

// parse json file
const read_artifact = (file_path) => {
  return JSON.parse(fs.readFileSync(file_path, "utf8"));
};

// gather all artifact files
const artifacts = all_files(path.join(cwd, "out"));

excludes = [
  "forge-std",
  "node_modules",
  "script",
  "test",
  "src/strategies/vendor/",
  "/out/",
  "toy_strategies",
  "CompoundModule",
  "AaveV2Module",
  "AaveV3Borrower",
  "lib/orbit-protocol/",
  "lib/openzeppelin/",
];

let anyFindings = false;
artifacts.forEach((file) => {
  const j = read_artifact(file);
  const fname = j.ast?.absolutePath;
  if (!fname || excludes.some((x) => fname.includes(x))) {
    return;
  }
  const relevant = j.ast.nodes
    .filter((x) => x.nodeType == "ContractDefinition")
    .map((x) => {
      if (!x?.documentation?.text?.includes("@title")) {
        anyFindings = true;
        console.log(`${fname} - ${x.name} missing @title`);
      }
      return x.nodes;
    })
    .flat();

  relevant
    .filter(
      (x) =>
        x.nodeType == "FunctionDefinition" ||
        x.nodeType == "EventDefinition" ||
        x.nodeType == "VariableDeclaration",
    )
    .forEach((x) => {
      const doc = x?.documentation?.text ?? "";
      if (doc.includes("@inheritdoc")) {
        return;
      }

      const name = x?.kind == "constructor" ? "constructor" : x.name;
      if (!doc.includes("@notice")) {
        anyFindings = true;
        console.log(`${fname}: ${name} - no description`);
      }
      x.returnParameters?.parameters.forEach((p) => {
        if (!doc.includes(`@return ${p.name}`)) {
          anyFindings = true;
          console.log(`${fname}: ${name} - ${p.name} (return)`);
        }
      });
      x.parameters?.parameters.forEach((p) => {
        if (!doc.includes(`@param ${p.name}`)) {
          anyFindings = true;
          console.log(`${fname}: ${name} - ${p.name}`);
        }
      });
    });
});

if (anyFindings) {
  throw new Error("Found missing natspec comments");
}
