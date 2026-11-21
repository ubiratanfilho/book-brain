// Collect notices from the installed, locked runtime packages for the app bundle.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));
const lock = JSON.parse(readFileSync(join(root, "package-lock.json"), "utf8"));
for (const [path, pkg] of Object.entries(lock.packages)) {
  if (!path || pkg.dev || (pkg.optional && !existsSync(join(root, path)))) continue;
  const dir = join(root, path);
  const files = readdirSync(dir, { withFileTypes: true })
    .filter(entry => entry.isFile() && /^(licen[sc]e|notice|copying)([.-]|$)/i.test(entry.name))
    .map(entry => entry.name);
  if (readdirSync(dir).includes("THIRD_PARTY_NOTICES")) {
    for (const file of readdirSync(join(dir, "THIRD_PARTY_NOTICES"))) files.push(join("THIRD_PARTY_NOTICES", file));
  }
  console.log(path, pkg.version, pkg.license ?? "");
  for (const file of files) console.log(readFileSync(join(dir, file), "utf8"));
}
