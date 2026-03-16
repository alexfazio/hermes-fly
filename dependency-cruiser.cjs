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
      name: "only-process-adapter-can-import-child-process",
      severity: "error",
      comment:
        "Only the process adapter may use child_process directly.",
      from: {
        pathNot: "^src/adapters/process\\.ts$"
      },
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
