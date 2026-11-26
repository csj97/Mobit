import { refreshCoins } from "./refresh.mjs";

Deno.serve(request => refreshCoins(request, Deno.env));
