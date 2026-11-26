import { notifyCommunity } from "./notify.mjs";

Deno.serve(request => notifyCommunity(request, Deno.env));
