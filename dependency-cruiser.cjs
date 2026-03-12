/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "no-domain-to-infrastructure-or-presentation",
      severity: "error",
      comment:
        "Domain logic must remain pure and cannot import infrastructure or presentation layers.",
      from: { path: "^src/contexts/[^/]+/domain/" },
      to: { path: "^src/contexts/[^/]+/(infrastructure|presentation)/" }
    },
    {
      name: "no-domain-to-legacy",
      severity: "error",
      comment: "Domain modules cannot import legacy bridge/runtime modules.",
      from: { path: "^src/contexts/[^/]+/domain/" },
      to: { path: "^src/legacy/" }
    },
    {
      name: "only-bash-bridge-can-import-child-process",
      severity: "error",
      comment:
        "Only the anti-corruption layer (bash-bridge) may use child_process directly.",
      from: { pathNot: "^src/legacy/bash-bridge\\.ts$" },
      to: { path: "^(node:)?child_process$" }
    }
  ],
  options: {
    includeOnly: "^src",
    doNotFollow: { path: "node_modules" },
    tsConfig: { fileName: "tsconfig.json" },
    enhancedResolveOptions: {
      extensions: [".ts", ".tsx", ".js", ".mjs", ".cjs"]
    }
  }
};
