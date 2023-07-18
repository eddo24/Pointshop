<h1>Bean's Pointshop</h1>

A market and inventory system addon for the sandbox game Garry's Mod.

This repo includes two serverside scripts from my project. The full project structure is not shown as I'll be publishing the completed addon for sale on gmodstore.com. As the project is still in development, some parts of these scripts are incomplete.

Bean's Pointshop is a cosmetics addon with two currencies, live item customisation, an inventory, a shop, and a market where players can bid for each others' items, or buy them outright.

<strong>sv_data.lua</strong> handles database management with SQL. SQL is used to preserve player inventories and shop/market stock through server downtime; during operation, the local cache is used wherever possible to minimise SQL calls. sv_data creates the database/cache operations that are called in sv_init.

<strong>sv_init.lua</strong> handles networking and hooks. This contains the functions called on receipt of client-server requests (e.g. transactions) and server-client data transfer (e.g. the shop stock). Hooks are used for object initialisation and tracking - the entities used to create ingame cosmetics.
