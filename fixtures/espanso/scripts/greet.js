// Greets the person in the earlier variable "who" (process.env.ESPANSO_WHO).
// Standard JavaScript only, so it runs under Bun and JavaScriptCore alike.
console.log(`Hallo ${process.env.ESPANSO_WHO ?? "daar"}!`);
