// Paste into the current subscription's extension script in Clash Verge Rev.
// Change the group name below if your subscription uses a different name.
function main(config) {
  config.rules = (config.rules || []).map(rule =>
    typeof rule === "string"
      ? rule.replace(
          /,\s*🇨🇳 国内网站\s*(?=,\s*no-resolve\s*$|$)/,
          ",DIRECT"
        )
      : rule
  );
  return config;
}
