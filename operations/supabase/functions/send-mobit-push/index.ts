import { sendPush } from "./push.mjs";

Deno.serve(request => sendPush(request, Deno.env));
