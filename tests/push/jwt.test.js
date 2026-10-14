// Checks the Edge Function's JWT signing helper (same code as supabase/functions/send-push) with a throwaway RSA key.
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const src = fs.readFileSync(path.join(__dirname, "../../supabase/functions/send-push/index.ts"), "utf8");
const code = src.split("// <jwt>")[1].split("// </jwt>")[0].replace(/: (any|string|number)/g, "");
const mod = new Function("crypto", "TextEncoder", "btoa", "atob", code + "; return {signJwt};")(crypto.webcrypto, TextEncoder, btoa, atob);
(async () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" });
  const jwt = await mod.signJwt({ client_email: "svc@p.iam.gserviceaccount.com", private_key: pem }, 1700000000);
  const [h, c, s] = jwt.split(".");
  const ok = crypto.verify("RSA-SHA256", Buffer.from(h + "." + c), publicKey, Buffer.from(s, "base64url"));
  const claim = JSON.parse(Buffer.from(c, "base64url").toString());
  const good = ok && claim.iss === "svc@p.iam.gserviceaccount.com" && claim.scope.endsWith("firebase.messaging") && claim.exp === 1700003600 && claim.aud === "https://oauth2.googleapis.com/token" && JSON.parse(Buffer.from(h, "base64url").toString()).alg === "RS256";
  console.log(good ? "PASS jwt signs and verifies" : "FAIL jwt"); process.exit(good ? 0 : 1);
})();
