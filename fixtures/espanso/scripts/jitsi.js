// Prints a random Jitsi room name. Optional first argument: length (default 10).
// Standard JavaScript only, so it runs under Bun and JavaScriptCore alike.
const length = Number(process.argv[2] ?? 10);
const chars = "abcdefghjkmnpqrstuvwxyz23456789";
let room = "";
for (let i = 0; i < length; i++) {
  room += chars[Math.floor(Math.random() * chars.length)];
}
console.log(room);
