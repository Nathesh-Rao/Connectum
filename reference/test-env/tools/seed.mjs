// Makes a fresh test organisation on a Connectum instance that shows sign-in codes (CONNECTUM_DEV_OTP=1: the dev instance or a local backend, never production),
// with the people and data the mobile app's automated tests start from, and prints what it made as JSON (nothing is stored but the data itself).
//
//   node tools/mobile-test/seed.mjs http://127.0.0.1:8181          (the backend's own port, e.g. through `ssh -f -N -L 8181:127.0.0.1:8080 connectum-dev`)
//   node tools/mobile-test/seed.mjs <BASE_URL> --prefix mt1        (names start with the prefix; default is a random one, so a run never clashes with an earlier one)
//
// What it makes (see docs/MOBILE_TEST_ENVIRONMENT.md for what it does NOT make):
//   * an organisation with branch HQ, departments Ops and Sales, the designation Analyst
//   * people: an administrator, two members (the owner and the assignee in the task flow), and one person OUTSIDE the organisation (an account of its own, in another organisation)
//   * a group (administrator, both members), and two to-do items: one the first member keeps, one sent to the second member
//   * the organisation's Connectum ID and the first member's personal code (for join and scan tests)
// Signing in as any of them needs no mailbox: POST /api/sd/login/start {email} answers with `devOtp`, then POST /api/sd/login/verify {email, otp}, then POST /api/sd/enter {enterprise} with the account token.
// Run it again for a clean set: every run is a new organisation.
import { bootstrap, seedOrg } from "../../connectum-backend/test/lib/harness.mjs";

const args = process.argv.slice(2);
const BASE = args.find((a) => /^https?:\/\//.test(a)) || "http://127.0.0.1:8181";
const at = args.indexOf("--prefix");
const prefix = (at >= 0 ? args[at + 1] : `mt${Math.random().toString(36).slice(2, 7)}`).replace(/[^a-z0-9]/gi, "").toLowerCase().slice(0, 12) || "mt";

async function main() {
    const B = await bootstrap(BASE, { org: `Mobile Test ${prefix}`, adminName: `${prefix}admin` });
    if (B.failed) throw new Error("this instance does not show sign-in codes (CONNECTUM_DEV_OTP=1), so it cannot be seeded: " + JSON.stringify(B.failed).slice(0, 200));
    const { A, connectUser, ent } = B;
    const owner = `${prefix}owner`, assignee = `${prefix}assignee`;
    await seedOrg(A, [[owner, "Olivia Owner", "Ops"], [assignee, "Arun Assignee", "Sales"]]);
    const O = await connectUser(owner), S = await connectUser(assignee);

    const group = await A.sd("group.create", { name: `${prefix} team`, members: [owner, assignee] });
    const kept = await O.sd("task.create", { title: "Prepare the monthly report", description: "Numbers from finance", priority: "high" });
    const sent = await O.sd("task.create", { title: "Review the draft", description: "Sent to the assignee" });
    const sentTo = sent.ok ? await O.sd("task.send", { id: sent.data?.task?.id ?? sent.data?.id, to: assignee }) : { ok: false };
    const orgInfo = await A.sd("connect.my");
    const ownerInfo = await O.sd("connect.my");

    // a person outside the organisation: an account of its own, in an organisation of its own
    const X = await bootstrap(BASE, { org: `Outside ${prefix}`, adminName: `${prefix}outside` });

    const emailOf = (u) => `${u}@test.co`;
    const out = {
        base: BASE,
        organisation: { name: `Mobile Test ${prefix}`, enterprise: ent, connectumId: orgInfo.data?.enterprise?.code ?? null },
        people: {
            admin: { username: `${prefix}admin`, email: emailOf(`${prefix}admin`) },
            owner: { username: owner, email: emailOf(owner), name: "Olivia Owner", code: ownerInfo.data?.person?.code ?? null },
            assignee: { username: assignee, email: emailOf(assignee), name: "Arun Assignee" },
            outsider: { username: `${prefix}outside`, email: emailOf(`${prefix}outside`), note: "belongs to another organisation (" + `Outside ${prefix}` + ")" },
        },
        group: group.ok ? { name: `${prefix} team` } : { error: group.error },
        tasks: { keptByOwner: kept.ok, sentToAssignee: sentTo.ok },
        signIn: "POST /api/sd/login/start {email} -> devOtp; POST /api/sd/login/verify {email, otp}; POST /api/sd/enter {enterprise} with the account token",
    };
    for (const c of [A, O, S, X.A]) { try { c.close(); } catch { /* ignore */ } }
    console.log(JSON.stringify(out, null, 2));
}
main().then(() => process.exit(0), (e) => { console.error("seed failed:", e.message); process.exit(1); });
